// Arc Testnet + deploy edilmis kontrat bilgileri
const CONFIG = {
  chainIdHex: "0x4cef52", // 5042002
  chainIdDec: 5042002,
  chainName: "Arc Testnet",
  rpcUrl: "https://rpc.testnet.arc.network",
  explorerUrl: "https://testnet.arcscan.app",
  nativeCurrency: { name: "USDC", symbol: "USDC", decimals: 18 },

  escrowAddress: "0x662B6eC9cc4fD8023806d95fCB9958c9794453cB",
  usdcAddress: "0x3600000000000000000000000000000000000000",
  usdcDecimals: 6,
};

const ERC20_ABI = [
  "function approve(address spender, uint256 amount) returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function balanceOf(address account) view returns (uint256)",
];
