// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {JobEscrow} from "../src/JobEscrow.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

contract JobEscrowTest is Test {
    JobEscrow public escrow;
    MockUSDC public usdc;

    address public employer = makeAddr("employer");
    address public worker = makeAddr("worker");
    address public stranger = makeAddr("stranger");

    uint256 public constant AMOUNT = 100_000_000; // 100 USDC (6 decimal)

    function setUp() public {
        usdc = new MockUSDC();
        escrow = new JobEscrow(address(usdc));

        usdc.mint(employer, 1_000_000_000); // 1000 USDC
        vm.prank(employer);
        usdc.approve(address(escrow), type(uint256).max);
    }

    function _createJob() internal returns (uint256 jobId) {
        vm.prank(employer);
        jobId = escrow.createJob(worker, AMOUNT, "test job");
    }

    // ---- createJob ----

    function test_CreateJob_LocksFundsInEscrow() public {
        uint256 jobId = _createJob();

        JobEscrow.Job memory job = escrow.getJob(jobId);
        assertEq(job.employer, employer);
        assertEq(job.worker, worker);
        assertEq(job.amount, AMOUNT);
        assertEq(uint8(job.status), uint8(JobEscrow.Status.Funded));

        assertEq(usdc.balanceOf(address(escrow)), AMOUNT);
        assertEq(usdc.balanceOf(employer), 1_000_000_000 - AMOUNT);
    }

    function test_RevertWhen_CreateJobWithZeroAmount() public {
        vm.prank(employer);
        vm.expectRevert(JobEscrow.InvalidAmount.selector);
        escrow.createJob(worker, 0, "bad job");
    }

    function test_RevertWhen_WorkerIsZeroAddress() public {
        vm.prank(employer);
        vm.expectRevert(JobEscrow.InvalidWorker.selector);
        escrow.createJob(address(0), AMOUNT, "bad job");
    }

    function test_RevertWhen_WorkerIsEmployerItself() public {
        vm.prank(employer);
        vm.expectRevert(JobEscrow.InvalidWorker.selector);
        escrow.createJob(employer, AMOUNT, "bad job");
    }

    function test_RevertWhen_NoAllowanceGiven() public {
        vm.prank(stranger); // stranger never approved the escrow contract
        vm.expectRevert();
        escrow.createJob(worker, AMOUNT, "no allowance");
    }

    // ---- approveJob ----

    function test_ApproveJob_TransfersFundsToWorker() public {
        uint256 jobId = _createJob();

        vm.prank(employer);
        escrow.approveJob(jobId);

        JobEscrow.Job memory job = escrow.getJob(jobId);
        assertEq(uint8(job.status), uint8(JobEscrow.Status.Completed));
        assertEq(usdc.balanceOf(worker), AMOUNT);
        assertEq(usdc.balanceOf(address(escrow)), 0);
    }

    function test_RevertWhen_NonEmployerApproves() public {
        uint256 jobId = _createJob();

        vm.prank(stranger);
        vm.expectRevert(JobEscrow.NotEmployer.selector);
        escrow.approveJob(jobId);
    }

    function test_RevertWhen_ApprovingAlreadyCompletedJob() public {
        uint256 jobId = _createJob();

        vm.prank(employer);
        escrow.approveJob(jobId);

        vm.prank(employer);
        vm.expectRevert(JobEscrow.JobNotFunded.selector);
        escrow.approveJob(jobId);
    }

    // ---- cancelJob ----

    function test_CancelJob_RefundsEmployer() public {
        uint256 jobId = _createJob();
        uint256 balanceBefore = usdc.balanceOf(employer);

        vm.prank(employer);
        escrow.cancelJob(jobId);

        JobEscrow.Job memory job = escrow.getJob(jobId);
        assertEq(uint8(job.status), uint8(JobEscrow.Status.Cancelled));
        assertEq(usdc.balanceOf(employer), balanceBefore + AMOUNT);
        assertEq(usdc.balanceOf(address(escrow)), 0);
    }

    function test_RevertWhen_NonEmployerCancels() public {
        uint256 jobId = _createJob();

        vm.prank(stranger);
        vm.expectRevert(JobEscrow.NotEmployer.selector);
        escrow.cancelJob(jobId);
    }

    function test_RevertWhen_CancellingAlreadyCompletedJob() public {
        uint256 jobId = _createJob();

        vm.prank(employer);
        escrow.approveJob(jobId);

        vm.prank(employer);
        vm.expectRevert(JobEscrow.JobNotFunded.selector);
        escrow.cancelJob(jobId);
    }

    function test_RevertWhen_CancellingAlreadyCancelledJob() public {
        uint256 jobId = _createJob();

        vm.prank(employer);
        escrow.cancelJob(jobId);

        vm.prank(employer);
        vm.expectRevert(JobEscrow.JobNotFunded.selector);
        escrow.cancelJob(jobId);
    }

    // ---- multiple jobs ----

    function test_MultipleJobsAreIndependent() public {
        uint256 jobId1 = _createJob();
        uint256 jobId2 = _createJob();

        vm.prank(employer);
        escrow.approveJob(jobId1);

        vm.prank(employer);
        escrow.cancelJob(jobId2);

        assertEq(uint8(escrow.getJob(jobId1).status), uint8(JobEscrow.Status.Completed));
        assertEq(uint8(escrow.getJob(jobId2).status), uint8(JobEscrow.Status.Cancelled));
    }
}
