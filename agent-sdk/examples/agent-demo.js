// Otonom AI Agent demo: iki cuzdan (employer-agent, worker-agent), insan mudahalesi
// olmadan Arc Testnet uzerinde gercek bir is-odeme dongusu tamamlar.
//
// Calistirmak icin: node examples/agent-demo.js  (agent-sdk/ klasorunden)
require("dotenv").config({ path: require("path").join(__dirname, "..", "..", ".env") });
const { ArcEscrowClient } = require("../client");

const CONFIG = {
  rpcUrl: process.env.ARC_TESTNET_RPC_URL,
  escrowAddress: "0xCc63109fE7A09C886b8145E31bA65e1bA9EB9448",
  usdcAddress: process.env.USDC_ADDRESS,
  explorerUrl: "https://testnet.arcscan.app",
};

function txLink(hash) {
  return `${CONFIG.explorerUrl}/tx/${hash}`;
}

async function main() {
  if (!process.env.AGENT_EMPLOYER_PK || !process.env.AGENT_WORKER_PK) {
    throw new Error("AGENT_EMPLOYER_PK / AGENT_WORKER_PK .env icinde tanimli degil.");
  }

  const employerAgent = new ArcEscrowClient({ ...CONFIG, privateKey: process.env.AGENT_EMPLOYER_PK });
  const workerAgent = new ArcEscrowClient({ ...CONFIG, privateKey: process.env.AGENT_WORKER_PK });

  console.log("== Arc Agent Escrow - Otonom Ajan Demosu ==\n");
  console.log(`Employer-agent : ${employerAgent.address}`);
  console.log(`Worker-agent   : ${workerAgent.address}\n`);

  // 1) Employer-agent, kimseye onceden atamadan acik bir is yayinlar.
  console.log("[employer-agent] Acik is olusturuluyor (0.05 USDC)...");
  const { jobId, txHash: createHash } = await employerAgent.createOpenJob({
    amountUsdc: "0.05",
    description: "Otonom ajan demo gorevi: metni ozetle",
  });
  console.log(`  -> Is #${jobId} olusturuldu. ${txLink(createHash)}\n`);

  // 2) Worker-agent isi kesfeder ve ustlenir (gercek bir ajan burada is listesini
  //    tarayip uygun bir is secebilir - bu demoda dogrudan yeni acilan isi aliyor).
  console.log("[worker-agent] Acik is bulundu, ustleniliyor...");
  const claimHash = await workerAgent.claimJob(jobId);
  console.log(`  -> Is ustlenildi. ${txLink(claimHash)}\n`);

  // 3) Worker-agent "isi yapar" (bu demoda simule ediliyor - gercek bir ajan burada
  //    bir LLM cagrisi yapip gercek bir teslimat uretebilir).
  console.log("[worker-agent] Is yapiliyor... (simule edildi: metin ozetlendi)\n");

  // 4) Employer-agent teslimati kontrol eder (simule) ve onaylar - USDC otomatik
  //    olarak worker-agent'in cuzdanina gecer.
  console.log("[employer-agent] Teslimat kontrol edildi, is onaylaniyor...");
  const approveHash = await employerAgent.approveJob(jobId);
  console.log(`  -> Is onaylandi, USDC worker-agent'e gonderildi. ${txLink(approveHash)}\n`);

  const finalJob = await employerAgent.getJob(jobId);
  const workerBalance = await workerAgent.usdcBalance();

  console.log("== Sonuc ==");
  console.log(`Is #${jobId} durumu : ${finalJob.statusName}`);
  console.log(`Worker-agent bakiyesi: ${workerBalance} USDC`);
  console.log(`\nTum akis tek bir insan onayi olmadan, iki otonom cuzdan arasinda tamamlandi.`);
}

main().catch((err) => {
  console.error("Demo basarisiz:", err);
  process.exit(1);
});
