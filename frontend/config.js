// Arc Testnet + deploy edilmis kontrat bilgileri
// Bu dosya degistiginde Vercel otomatik olarak yeniden deploy eder (GitHub baglantisi).
const CONFIG = {
  chainIdHex: "0x4cef52", // 5042002
  chainIdDec: 5042002,
  chainName: "Arc Testnet",
  rpcUrl: "https://rpc.testnet.arc.network",
  explorerUrl: "https://testnet.arcscan.app",
  nativeCurrency: { name: "USDC", symbol: "USDC", decimals: 18 },

  escrowAddress: "0x2E884D26978EA9120ba21445abe1f7Fd8144a114",
  usdcAddress: "0x3600000000000000000000000000000000000000",
  usdcDecimals: 6,
};

const ERC20_ABI = [
  "function approve(address spender, uint256 amount) returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function balanceOf(address account) view returns (uint256)",
];
