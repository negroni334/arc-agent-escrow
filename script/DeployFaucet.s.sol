// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Faucet} from "../src/Faucet.sol";

/// @notice Arc Testnet'e Faucet kontratini deploy eder ve baslangic USDC havuzuyla doldurur.
/// @dev Kullanim: forge script script/DeployFaucet.s.sol --rpc-url arc_testnet --broadcast
///      FAUCET_FUND_AMOUNT env degiskeni (6 decimal, orn. 3000000 = 3 USDC) opsiyoneldir,
///      verilmezse havuz doldurulmaz.
contract DeployFaucetScript is Script {
    function run() external returns (Faucet faucet) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        uint256 fundAmount = vm.envOr("FAUCET_FUND_AMOUNT", uint256(0));

        vm.startBroadcast(deployerPrivateKey);
        faucet = new Faucet(usdcAddress);

        if (fundAmount > 0) {
            IERC20(usdcAddress).approve(address(faucet), fundAmount);
            faucet.fund(fundAmount);
        }
        vm.stopBroadcast();

        console.log("Faucet deployed at:", address(faucet));
        console.log("Funded with:", fundAmount);
    }
}
