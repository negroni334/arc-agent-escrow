# Arc Agent Escrow SDK

Node.js SDK ve otonom demo — AI ajanlarinin (ya da herhangi bir script'in) Arc Testnet
uzerindeki `JobEscrow` kontratiyla **hicbir web arayuzune ihtiyac duymadan**, dogrudan
programatik olarak etkilesmesi icin.

## Neden var?

Ana proje ("Arc Agent Escrow") adindan da anlasilacagi gibi AI ajanlarinin birbirine is
verip odeme yaptigi bir sistem iddia ediyor — ama bir web dApp'i tek basina bunu kanitlamiyor,
cunku sonunda hep bir insan MetaMask'ta tikliyor. Bu SDK ve asagidaki demo, **iki otonom
cuzdanin, tek bir insan onayi olmadan, gercek testnet uzerinde is olusturup / ustlenip /
onaylayip parayi el degistirdigini** gosteriyor.

## Kurulum

```bash
cd agent-sdk
npm install
```

## Otonom demo'yu calistirma

Kok dizindeki `.env` dosyasinda `AGENT_EMPLOYER_PK` ve `AGENT_WORKER_PK` tanimli olmali
(testnet-only, gercek fonu olmayan cuzdanlar — gaz icin birkac USDC'ye ihtiyaclari var,
ana cuzdanindan ya da [mini faucet'ten](../frontend/index.html) gonderebilirsin).

```bash
npm run demo
# ya da: node examples/agent-demo.js
```

Demo sirasiyla sunu yapar (hepsi gercek Arc Testnet islemleri, tx linkleriyle):
1. **employer-agent** kimseye onceden atamadan acik bir is yayinlar (`createOpenJob`)
2. **worker-agent** isi kesfedip ustlenir (`claimJob`)
3. worker-agent isi yapar (bu demoda simule edilir — gercek bir ajan burada bir LLM
   cagrisi yapip gercek bir teslimat uretebilir)
4. **employer-agent** teslimati onaylar (`approveJob`) — USDC otomatik worker-agent'e gecer

## `ArcEscrowClient` API'si

```js
const { ArcEscrowClient } = require("./client");

const client = new ArcEscrowClient({
  rpcUrl: "https://rpc.testnet.arc.network",
  escrowAddress: "0x...",
  usdcAddress: "0x3600000000000000000000000000000000000000",
  privateKey: "0x...", // opsiyonel - verilmezse client salt-okunur olur
});

await client.createJob({ worker, arbiter, amountUsdc, description });
await client.createOpenJob({ amountUsdc, description }); // worker belirtmeden
await client.claimJob(jobId);
await client.approveJob(jobId);
await client.cancelJob(jobId);
await client.raiseDispute(jobId);
await client.getJob(jobId);
await client.getReputation(address);
await client.usdcBalance(address);
```

ABI, frontend ile ayni kaynaktan (`../frontend/vendor/jobescrow-abi.json`) okunur —
iki taraf da her zaman senkron kalir, ayri bir kopya tutulmaz.
