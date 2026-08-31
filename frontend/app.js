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
  return ["-", "Funded (Bekliyor)", "Completed (Tamamlandi)", "Cancelled (Iptal)"][statusNum] || "?";
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

  const isFunded = Number(job.status) === 1;
  const isEmployer = userAddress && userAddress.toLowerCase() === job.employer.toLowerCase();

  div.innerHTML = `
    <div class="job-top">
      <span class="job-id">#${job.id}</span>
      <span class="job-status status-${job.status}">${statusLabel(Number(job.status))}</span>
    </div>
    <p class="job-desc">${job.description}</p>
    <div class="job-meta">
      <div><span>Isveren</span><code>${shortAddr(job.employer)}</code></div>
      <div><span>Isci</span><code>${shortAddr(job.worker)}</code></div>
      <div><span>Miktar</span><code>${amountUsdc} USDC</code></div>
    </div>
    ${
      isFunded && isEmployer
        ? `<div class="job-actions">
             <button class="btn primary small" data-action="approve" data-id="${job.id}">Onayla</button>
             <button class="btn danger small" data-action="cancel" data-id="${job.id}">Iptal Et</button>
           </div>`
        : ""
    }
  `;

  div.querySelectorAll("button[data-action]").forEach((btn) => {
    btn.addEventListener("click", () => handleJobAction(btn.dataset.action, Number(btn.dataset.id), btn));
  });

  return div;
}

async function handleJobAction(action, jobId, btn) {
  try {
    btn.disabled = true;
    const original = btn.textContent;
    btn.textContent = "Isleniyor...";
    clearStatus();

    const contract = await getWriteContract();
    const tx = action === "approve" ? await contract.approveJob(jobId) : await contract.cancelJob(jobId);
    showStatus(`Islem gonderildi: ${tx.hash} - onay bekleniyor...`, "info");
    await tx.wait();
    showStatus(`Is #${jobId} ${action === "approve" ? "onaylandi" : "iptal edildi"}.`, "success");

    btn.textContent = original;
    await refreshJobs();
  } catch (err) {
    console.error(err);
    showStatus(`Islem basarisiz: ${err.shortMessage || err.message || err}`, "error");
    btn.disabled = false;
    btn.textContent = action === "approve" ? "Onayla" : "Iptal Et";
  }
}

async function handleCreateJob(e) {
  e.preventDefault();
  const btn = el("createJobBtn");
  const worker = el("workerInput").value.trim();
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
    const tx = await contract.createJob(worker, amount, description);
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
