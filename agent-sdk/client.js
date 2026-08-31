const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

const JOB_ESCROW_ABI = JSON.parse(
  fs.readFileSync(path.join(__dirname, "..", "frontend", "vendor", "jobescrow-abi.json"), "utf8")
);

const ERC20_ABI = [
  "function approve(address spender, uint256 amount) returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function balanceOf(address account) view returns (uint256)",
];

const STATUS_NAMES = ["None", "Funded", "Completed", "Cancelled", "Disputed"];

/**
 * ArcEscrowClient - Arc Testnet'teki JobEscrow kontratiyla programatik olarak
 * etkilesmek isteyen AI ajanlari / script'ler icin ince bir ethers.js v6 wrapper'i.
 */
class ArcEscrowClient {
  constructor({ rpcUrl, escrowAddress, usdcAddress, privateKey, usdcDecimals = 6 }) {
    this.provider = new ethers.JsonRpcProvider(rpcUrl);
    this.wallet = privateKey ? new ethers.Wallet(privateKey, this.provider) : null;
    this.escrowAddress = escrowAddress;
    this.usdcAddress = usdcAddress;
    this.usdcDecimals = usdcDecimals;

    const runner = this.wallet || this.provider;
    this.escrow = new ethers.Contract(escrowAddress, JOB_ESCROW_ABI, runner);
    this.usdc = new ethers.Contract(usdcAddress, ERC20_ABI, runner);
  }

  get address() {
    if (!this.wallet) throw new Error("Bu client salt-okunur (privateKey verilmedi).");
    return this.wallet.address;
  }

  toUnits(amountHuman) {
    return ethers.parseUnits(String(amountHuman), this.usdcDecimals);
  }

  async ensureAllowance(amount) {
    const current = await this.usdc.allowance(this.address, this.escrowAddress);
    if (current >= amount) return null;
    const tx = await this.usdc.approve(this.escrowAddress, amount);
    await tx.wait();
    return tx.hash;
  }

  async createJob({ worker, arbiter = ethers.ZeroAddress, amountUsdc, description }) {
    const amount = this.toUnits(amountUsdc);
    await this.ensureAllowance(amount);
    const tx = await this.escrow.createJob(worker, arbiter, amount, description);
    const receipt = await tx.wait();
    return { jobId: await this._jobIdFromReceipt(receipt), txHash: tx.hash };
  }

  async createOpenJob({ arbiter = ethers.ZeroAddress, amountUsdc, description }) {
    return this.createJob({ worker: ethers.ZeroAddress, arbiter, amountUsdc, description });
  }

  async claimJob(jobId) {
    const tx = await this.escrow.claimJob(jobId);
    await tx.wait();
    return tx.hash;
  }

  async approveJob(jobId) {
    const tx = await this.escrow.approveJob(jobId);
    await tx.wait();
    return tx.hash;
  }

  async cancelJob(jobId) {
    const tx = await this.escrow.cancelJob(jobId);
    await tx.wait();
    return tx.hash;
  }

  async raiseDispute(jobId) {
    const tx = await this.escrow.raiseDispute(jobId);
    await tx.wait();
    return tx.hash;
  }

  async getJob(jobId) {
    const job = await this.escrow.getJob(jobId);
    return {
      employer: job.employer,
      worker: job.worker,
      arbiter: job.arbiter,
      amount: job.amount,
      amountUsdc: ethers.formatUnits(job.amount, this.usdcDecimals),
      status: Number(job.status),
      statusName: STATUS_NAMES[Number(job.status)] || "Unknown",
      description: job.description,
    };
  }

  async getReputation(address) {
    const [employerCompleted, employerCancelled, workerCompleted] = await Promise.all([
      this.escrow.queryFilter(this.escrow.filters.JobApproved(null, address)),
      this.escrow.queryFilter(this.escrow.filters.JobCancelled(null, address)),
      this.escrow.queryFilter(this.escrow.filters.JobApproved(null, null, address)),
    ]);
    return {
      employerCompleted: employerCompleted.length,
      employerCancelled: employerCancelled.length,
      workerCompleted: workerCompleted.length,
    };
  }

  async usdcBalance(address = this.address) {
    const raw = await this.usdc.balanceOf(address);
    return ethers.formatUnits(raw, this.usdcDecimals);
  }

  async _jobIdFromReceipt(receipt) {
    const iface = new ethers.Interface(JOB_ESCROW_ABI);
    for (const log of receipt.logs) {
      try {
        const parsed = iface.parseLog(log);
        if (parsed?.name === "JobCreated") return Number(parsed.args.jobId);
      } catch {
        // bu kontrata ait olmayan bir log, atla
      }
    }
    throw new Error("JobCreated event'i receipt icinde bulunamadi.");
  }
}

module.exports = { ArcEscrowClient, STATUS_NAMES };
