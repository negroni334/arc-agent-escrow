let jobEscrowAbi = null;
let provider = null; // read-only provider (public RPC), always available
let browserProvider = null; // MetaMask provider, only after connect
let signer = null;
let userAddress = null;

const el = (id) => document.getElementById(id);
const statusMsg = el("statusMsg");
const connectBtn = el("connectBtn");
const networkBadge = el("networkBadge");
const addressBadge = el("addressBadge");
const jobsList = el("jobsList");
const jobsEmpty = el("jobsEmpty");
const contractLink = el("contractLink");

contractLink.href = `${CONFIG.explorerUrl}/address/${CONFIG.escrowAddress}`;
contractLink.textContent = `${CONFIG.escrowAddress.slice(0, 6)}...${CONFIG.escrowAddress.slice(-4)}`;

function showStatus(text, kind = "info") {
  statusMsg.textContent = text;
  statusMsg.className = `status ${kind}`;
  statusMsg.classList.remove("hidden");
}

function clearStatus() {
  statusMsg.classList.add("hidden");
}

function shortAddr(addr) {
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

function statusLabel(statusNum) {
  return ["-", "Funded (Bekliyor)", "Completed (Tamamlandi)", "Cancelled (Iptal)", "Disputed (Anlasmazlik)"][
    statusNum
  ] || "?";
}

function isZeroAddress(addr) {
  return !addr || addr.toLowerCase() === "0x0000000000000000000000000000000000000000";
}

async function loadAbi() {
  if (jobEscrowAbi) return jobEscrowAbi;
  const res = await fetch("vendor/jobescrow-abi.json");
  jobEscrowAbi = await res.json();
  return jobEscrowAbi;
}

async function getReadOnlyContract() {
  await loadAbi();
  if (!provider) {
    provider = new ethers.JsonRpcProvider(CONFIG.rpcUrl, CONFIG.chainIdDec);
  }
  return new ethers.Contract(CONFIG.escrowAddress, jobEscrowAbi, provider);
}

async function getWriteContract() {
  await loadAbi();
  if (!signer) throw new Error("Once cuzdanini bagla.");
  return new ethers.Contract(CONFIG.escrowAddress, jobEscrowAbi, signer);
}

async function ensureArcNetwork() {
  if (!window.ethereum) throw new Error("MetaMask bulunamadi.");
  try {
    await window.ethereum.request({
      method: "wallet_switchEthereumChain",
      params: [{ chainId: CONFIG.chainIdHex }],
    });
  } catch (switchError) {
    if (switchError.code === 4902) {
      await window.ethereum.request({
        method: "wallet_addEthereumChain",
        params: [
          {
            chainId: CONFIG.chainIdHex,
            chainName: CONFIG.chainName,
            rpcUrls: [CONFIG.rpcUrl],
            nativeCurrency: CONFIG.nativeCurrency,
            blockExplorerUrls: [CONFIG.explorerUrl],
          },
        ],
      });
    } else {
      throw switchError;
    }
  }
}

async function connectWallet() {
  if (!window.ethereum) {
    showStatus("MetaMask (ya da uyumlu bir cuzdan uzantisi) bulunamadi. Lutfen kurup tekrar dene.", "error");
    return;
  }
  try {
    clearStatus();
    connectBtn.disabled = true;
    connectBtn.textContent = "Baglaniyor...";

    await ensureArcNetwork();

    browserProvider = new ethers.BrowserProvider(window.ethereum);
    await browserProvider.send("eth_requestAccounts", []);
    signer = await browserProvider.getSigner();
    userAddress = await signer.getAddress();

    networkBadge.textContent = CONFIG.chainName;
    networkBadge.classList.remove("hidden");
    addressBadge.textContent = shortAddr(userAddress);
    addressBadge.classList.remove("hidden");
    connectBtn.textContent = "Baglandi";

    await refreshJobs();
  } catch (err) {
    console.error(err);
    showStatus(`Baglanti hatasi: ${err.message || err}`, "error");
    connectBtn.disabled = false;
    connectBtn.textContent = "Cuzdani Bagla";
  }
}

async function refreshJobs() {
  jobsList.innerHTML = "";
  try {
    const contract = await getReadOnlyContract();
    const count = await contract.jobCount();
    const total = Number(count);

    if (total === 0) {
      jobsEmpty.textContent = "Henuz hic is olusturulmadi.";
      jobsEmpty.classList.remove("hidden");
      return;
    }

    const jobs = [];
    for (let i = total - 1; i >= 0; i--) {
      const job = await contract.getJob(i);
      jobs.push({
        id: i,
        employer: job.employer,
        worker: job.worker,
        arbiter: job.arbiter,
        amount: job.amount,
        status: job.status,
        description: job.description,
      });
    }

    jobsEmpty.classList.add("hidden");
    for (const job of jobs) {
      jobsList.appendChild(renderJobCard(job));
    }
  } catch (err) {
    console.error(err);
    jobsEmpty.textContent = `Isler yuklenemedi: ${err.message || err}`;
    jobsEmpty.classList.remove("hidden");
  }
}

function renderJobCard(job) {
  const amountUsdc = ethers.formatUnits(job.amount, CONFIG.usdcDecimals);
  const div = document.createElement("div");
  div.className = "job-card";

  const statusNum = Number(job.status);
  const isFunded = statusNum === 1;
  const isDisputed = statusNum === 4;
  const hasArbiter = !isZeroAddress(job.arbiter);

  const isEmployer = userAddress && userAddress.toLowerCase() === job.employer.toLowerCase();
  const isWorker = userAddress && userAddress.toLowerCase() === job.worker.toLowerCase();
  const isArbiter = userAddress && hasArbiter && userAddress.toLowerCase() === job.arbiter.toLowerCase();

  let actionsHtml = "";
  if (isFunded && isEmployer) {
    actionsHtml = `
      <div class="job-actions">
        <button class="btn primary small" data-action="approve" data-id="${job.id}">Onayla</button>
        <button class="btn danger small" data-action="cancel" data-id="${job.id}">Iptal Et</button>
      </div>`;
  } else if (isFunded && isWorker && hasArbiter) {
    actionsHtml = `
      <div class="job-actions">
        <button class="btn danger small" data-action="dispute" data-id="${job.id}">Anlasmazlik Ac</button>
      </div>`;
  } else if (isDisputed && isArbiter) {
    actionsHtml = `
      <div class="job-actions">
        <button class="btn primary small" data-action="resolveWorker" data-id="${job.id}">Isciye Ver</button>
        <button class="btn danger small" data-action="resolveEmployer" data-id="${job.id}">Isverene Iade Et</button>
      </div>`;
  }

  div.innerHTML = `
    <div class="job-top">
      <span class="job-id">#${job.id}</span>
      <span class="job-status status-${statusNum}">${statusLabel(statusNum)}</span>
    </div>
    <p class="job-desc">${job.description}</p>
    <div class="job-meta">
      <div><span>Isveren</span><code>${shortAddr(job.employer)}</code></div>
      <div><span>Isci</span><code>${shortAddr(job.worker)}</code></div>
      <div><span>Hakem</span><code>${hasArbiter ? shortAddr(job.arbiter) : "yok"}</code></div>
      <div><span>Miktar</span><code>${amountUsdc} USDC</code></div>
    </div>
    ${actionsHtml}
  `;

  div.querySelectorAll("button[data-action]").forEach((btn) => {
    btn.addEventListener("click", () => handleJobAction(btn.dataset.action, Number(btn.dataset.id), btn));
  });

  return div;
}

const ACTION_LABELS = {
  approve: "Onayla",
  cancel: "Iptal Et",
  dispute: "Anlasmazlik Ac",
  resolveWorker: "Isciye Ver",
  resolveEmployer: "Isverene Iade Et",
};

async function handleJobAction(action, jobId, btn) {
  try {
    btn.disabled = true;
    btn.textContent = "Isleniyor...";
    clearStatus();

    const contract = await getWriteContract();
    let tx;
    if (action === "approve") tx = await contract.approveJob(jobId);
    else if (action === "cancel") tx = await contract.cancelJob(jobId);
    else if (action === "dispute") tx = await contract.raiseDispute(jobId);
    else if (action === "resolveWorker") tx = await contract.resolveDispute(jobId, true);
    else if (action === "resolveEmployer") tx = await contract.resolveDispute(jobId, false);
    else throw new Error(`Bilinmeyen islem: ${action}`);

    showStatus(`Islem gonderildi: ${tx.hash} - onay bekleniyor...`, "info");
    await tx.wait();
    showStatus(`Is #${jobId}: "${ACTION_LABELS[action]}" islemi basariyla tamamlandi.`, "success");

    await refreshJobs();
  } catch (err) {
    console.error(err);
    showStatus(`Islem basarisiz: ${err.shortMessage || err.message || err}`, "error");
    btn.disabled = false;
    btn.textContent = ACTION_LABELS[action] || "Tekrar dene";
  }
}

async function handleCreateJob(e) {
  e.preventDefault();
  const btn = el("createJobBtn");
  const worker = el("workerInput").value.trim();
  const arbiterRaw = el("arbiterInput").value.trim();
  const amountHuman = el("amountInput").value.trim();
  const description = el("descriptionInput").value.trim();

  if (!signer) {
    showStatus("Once cuzdanini bagla.", "error");
    return;
  }
  if (!ethers.isAddress(worker)) {
    showStatus("Gecerli bir isci cuzdan adresi gir.", "error");
    return;
  }
  const arbiter = arbiterRaw === "" ? ethers.ZeroAddress : arbiterRaw;
  if (!ethers.isAddress(arbiter)) {
    showStatus("Hakem adresi girdiysen gecerli bir adres olmali (ya da bos birak).", "error");
    return;
  }

  try {
    btn.disabled = true;
    clearStatus();

    const amount = ethers.parseUnits(amountHuman, CONFIG.usdcDecimals);

    const usdc = new ethers.Contract(CONFIG.usdcAddress, ERC20_ABI, signer);
    const currentAllowance = await usdc.allowance(userAddress, CONFIG.escrowAddress);

    if (currentAllowance < amount) {
      btn.textContent = "1/2 Approve icin cuzdanini onayla...";
      const approveTx = await usdc.approve(CONFIG.escrowAddress, amount);
      showStatus(`Approve gonderildi: ${approveTx.hash} - onay bekleniyor...`, "info");
      await approveTx.wait();
    }

    btn.textContent = "2/2 Is olusturuluyor...";
    const contract = await getWriteContract();
    const tx = await contract.createJob(worker, arbiter, amount, description);
    showStatus(`createJob gonderildi: ${tx.hash} - onay bekleniyor...`, "info");
    await tx.wait();

    showStatus("Is basariyla olusturuldu ve USDC kilitlendi.", "success");
    el("createJobForm").reset();
    await refreshJobs();
  } catch (err) {
    console.error(err);
    showStatus(`Islem basarisiz: ${err.shortMessage || err.message || err}`, "error");
  } finally {
    btn.disabled = false;
    btn.textContent = "Is Olustur (Approve + Create)";
  }
}

connectBtn.addEventListener("click", connectWallet);
el("refreshBtn").addEventListener("click", refreshJobs);
el("createJobForm").addEventListener("submit", handleCreateJob);

if (window.ethereum) {
  window.ethereum.on?.("accountsChanged", () => window.location.reload());
  window.ethereum.on?.("chainChanged", () => window.location.reload());
}

// Cuzdan baglanmasa bile is listesini salt-okunur RPC ile goster
refreshJobs();
