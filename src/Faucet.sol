// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Faucet
/// @notice Arc Agent Escrow dApp'ini denemek isteyenler icin kucuk, rate-limitli bir USDC
///         dagitici. Sinirsiz bir kaynak degil - sadece dApp'i denemeye yetecek kucuk bir
///         miktar (varsayilan 0.5 USDC) verir, adres basina gunde bir kez.
/// @dev Havuz, sahibi (owner) tarafindan `fund` ile doldurulur. Kotuye kullanimi onlemek icin
///      cooldown tamamen zincir uzerinde, herkese acik ve denetlenebilir sekilde tutulur.
contract Faucet is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable USDC;
    uint256 public constant CLAIM_AMOUNT = 500_000; // 0.5 USDC (6 decimal)
    uint256 public constant COOLDOWN = 1 days;

    mapping(address => uint256) public lastClaimedAt;

    event Claimed(address indexed claimer, uint256 amount, uint256 timestamp);
    event Funded(address indexed funder, uint256 amount);

    error TooSoon(uint256 nextClaimAt);
    error InsufficientFaucetBalance();

    constructor(address usdcAddress) Ownable(msg.sender) {
        USDC = IERC20(usdcAddress);
    }

    /// @notice Havuzdan sabit miktarda (CLAIM_AMOUNT) USDC talep eder.
    /// @dev Ayni adres, COOLDOWN suresi dolmadan tekrar cagiramaz.
    function claim() external {
        uint256 last = lastClaimedAt[msg.sender];
        if (last != 0) {
            uint256 nextAllowed = last + COOLDOWN;
            if (block.timestamp < nextAllowed) revert TooSoon(nextAllowed);
        }
        if (USDC.balanceOf(address(this)) < CLAIM_AMOUNT) revert InsufficientFaucetBalance();

        lastClaimedAt[msg.sender] = block.timestamp;
        USDC.safeTransfer(msg.sender, CLAIM_AMOUNT);

        emit Claimed(msg.sender, CLAIM_AMOUNT, block.timestamp);
    }

    /// @notice Havuza USDC ekler. Herkes doldurabilir, sadece sahip cekebilir.
    /// @dev Cagirmadan once `amount` kadar USDC harcama izni (approve) verilmis olmali.
    function fund(uint256 amount) external {
        USDC.safeTransferFrom(msg.sender, address(this), amount);
        emit Funded(msg.sender, amount);
    }

    /// @notice `account` adresinin bir sonraki claim'e kadar beklemesi gereken saniye.
    /// @return Beklenmesi gereken saniye; hemen claim edebiliyorsa 0.
    function timeUntilNextClaim(address account) external view returns (uint256) {
        uint256 last = lastClaimedAt[account];
        if (last == 0) return 0;
        uint256 nextAllowed = last + COOLDOWN;
        if (block.timestamp >= nextAllowed) return 0;
        return nextAllowed - block.timestamp;
    }

    /// @notice Acil durumda sahibin havuzdaki USDC'yi geri cekmesi icin.
    function emergencyWithdraw(uint256 amount) external onlyOwner {
        USDC.safeTransfer(owner(), amount);
    }
}
