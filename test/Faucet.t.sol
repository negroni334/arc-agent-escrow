// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Faucet} from "../src/Faucet.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

contract FaucetTest is Test {
    Faucet public faucet;
    MockUSDC public usdc;

    address public owner = address(this);
    address public funder = makeAddr("funder");
    address public claimer = makeAddr("claimer");
    address public otherClaimer = makeAddr("otherClaimer");

    uint256 public constant POOL_AMOUNT = 10_000_000; // 10 USDC

    function setUp() public {
        usdc = new MockUSDC();
        faucet = new Faucet(address(usdc));

        usdc.mint(funder, POOL_AMOUNT);
        vm.prank(funder);
        usdc.approve(address(faucet), type(uint256).max);
        vm.prank(funder);
        faucet.fund(POOL_AMOUNT);
    }

    function test_Fund_IncreasesPoolBalance() public view {
        assertEq(usdc.balanceOf(address(faucet)), POOL_AMOUNT);
    }

    function test_Claim_TransfersFixedAmount() public {
        vm.prank(claimer);
        faucet.claim();

        assertEq(usdc.balanceOf(claimer), faucet.CLAIM_AMOUNT());
        assertEq(usdc.balanceOf(address(faucet)), POOL_AMOUNT - faucet.CLAIM_AMOUNT());
    }

    function test_RevertWhen_ClaimingTwiceWithinCooldown() public {
        vm.prank(claimer);
        faucet.claim();

        vm.prank(claimer);
        vm.expectRevert();
        faucet.claim();
    }

    function test_Claim_AllowedAfterCooldownPasses() public {
        vm.prank(claimer);
        faucet.claim();

        vm.warp(block.timestamp + faucet.COOLDOWN() + 1);

        vm.prank(claimer);
        faucet.claim();

        assertEq(usdc.balanceOf(claimer), faucet.CLAIM_AMOUNT() * 2);
    }

    function test_DifferentClaimers_AreIndependent() public {
        vm.prank(claimer);
        faucet.claim();

        vm.prank(otherClaimer);
        faucet.claim();

        assertEq(usdc.balanceOf(claimer), faucet.CLAIM_AMOUNT());
        assertEq(usdc.balanceOf(otherClaimer), faucet.CLAIM_AMOUNT());
    }

    function test_RevertWhen_PoolIsEmpty() public {
        // Havuzu bosalt: sahip her seyi geri ceksin
        faucet.emergencyWithdraw(POOL_AMOUNT);

        vm.prank(claimer);
        vm.expectRevert(Faucet.InsufficientFaucetBalance.selector);
        faucet.claim();
    }

    function test_TimeUntilNextClaim_ZeroWhenNeverClaimed() public view {
        assertEq(faucet.timeUntilNextClaim(claimer), 0);
    }

    function test_TimeUntilNextClaim_PositiveRightAfterClaim() public {
        vm.prank(claimer);
        faucet.claim();

        assertEq(faucet.timeUntilNextClaim(claimer), faucet.COOLDOWN());
    }

    function test_EmergencyWithdraw_OnlyOwner() public {
        vm.prank(claimer);
        vm.expectRevert();
        faucet.emergencyWithdraw(1);
    }

    function test_EmergencyWithdraw_TransfersToOwner() public {
        uint256 before = usdc.balanceOf(owner);
        faucet.emergencyWithdraw(POOL_AMOUNT);
        assertEq(usdc.balanceOf(owner), before + POOL_AMOUNT);
    }
}
