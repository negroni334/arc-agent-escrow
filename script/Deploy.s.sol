// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {JobEscrow} from "../src/JobEscrow.sol";

/// @notice Arc Testnet'e JobEscrow kontratini deploy eder.
/// @dev Kullanim: forge script script/Deploy.s.sol --rpc-url arc_testnet --broadcast
contract DeployScript is Script {
    function run() external returns (JobEscrow escrow) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address usdcAddress = vm.envAddress("USDC_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);
        escrow = new JobEscrow(usdcAddress);
        vm.stopBroadcast();

        console.log("JobEscrow deployed at:", address(escrow));
        console.log("USDC address used:", usdcAddress);
    }
}
