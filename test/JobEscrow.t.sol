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
    address public arbiter = makeAddr("arbiter");
    address public stranger = makeAddr("stranger");

    uint256 public constant EMPLOYER_BALANCE = 1_000_000_000; // 1000 USDC
    uint256 public constant AMOUNT = 100_000_000; // 100 USDC (6 decimal)

    function setUp() public {
        usdc = new MockUSDC();
        escrow = new JobEscrow(address(usdc));

        usdc.mint(employer, EMPLOYER_BALANCE);
        vm.prank(employer);
        usdc.approve(address(escrow), type(uint256).max);
    }

    function _createJob() internal returns (uint256 jobId) {
        vm.prank(employer);
        jobId = escrow.createJob(worker, arbiter, AMOUNT, "test job");
    }

    function _createJobNoArbiter() internal returns (uint256 jobId) {
        vm.prank(employer);
        jobId = escrow.createJob(worker, address(0), AMOUNT, "test job, no arbiter");
    }

    function _createOpenJob() internal returns (uint256 jobId) {
        vm.prank(employer);
        jobId = escrow.createJob(address(0), arbiter, AMOUNT, "open job");
    }

    // ---- createJob ----

    function test_CreateJob_LocksFundsInEscrow() public {
        uint256 jobId = _createJob();

        JobEscrow.Job memory job = escrow.getJob(jobId);
        assertEq(job.employer, employer);
        assertEq(job.worker, worker);
        assertEq(job.arbiter, arbiter);
        assertEq(job.amount, AMOUNT);
        assertEq(uint8(job.status), uint8(JobEscrow.Status.Funded));

        assertEq(usdc.balanceOf(address(escrow)), AMOUNT);
        assertEq(usdc.balanceOf(employer), EMPLOYER_BALANCE - AMOUNT);
    }

    function test_CreateJob_WithoutArbiter() public {
        uint256 jobId = _createJobNoArbiter();
        assertEq(escrow.getJob(jobId).arbiter, address(0));
    }

    function test_RevertWhen_CreateJobWithZeroAmount() public {
        vm.prank(employer);
        vm.expectRevert(JobEscrow.InvalidAmount.selector);
        escrow.createJob(worker, arbiter, 0, "bad job");
    }

    function test_CreateJob_OpenJob_WorkerIsZeroAddress() public {
        uint256 jobId = _createOpenJob();

        JobEscrow.Job memory job = escrow.getJob(jobId);
        assertEq(job.worker, address(0));
        assertEq(uint8(job.status), uint8(JobEscrow.Status.Funded));
        // Para yine de kilitlenmis olmali, worker henuz atanmamis olsa da.
        assertEq(usdc.balanceOf(address(escrow)), AMOUNT);
    }

    function test_CreateJob_OpenJobWithNoArbiter_Succeeds() public {
        vm.prank(employer);
        uint256 jobId = escrow.createJob(address(0), address(0), AMOUNT, "open, no arbiter");
        assertEq(escrow.getJob(jobId).worker, address(0));
        assertEq(escrow.getJob(jobId).arbiter, address(0));
    }

    function test_RevertWhen_WorkerIsEmployerItself() public {
        vm.prank(employer);
        vm.expectRevert(JobEscrow.InvalidWorker.selector);
        escrow.createJob(employer, arbiter, AMOUNT, "bad job");
    }

    function test_RevertWhen_ArbiterIsEmployerItself() public {
        vm.prank(employer);
        vm.expectRevert(JobEscrow.InvalidArbiter.selector);
        escrow.createJob(worker, employer, AMOUNT, "bad job");
    }

    function test_RevertWhen_ArbiterIsWorkerItself() public {
        vm.prank(employer);
        vm.expectRevert(JobEscrow.InvalidArbiter.selector);
        escrow.createJob(worker, worker, AMOUNT, "bad job");
    }

    function test_RevertWhen_NoAllowanceGiven() public {
        vm.prank(stranger); // stranger never approved the escrow contract
        vm.expectRevert();
        escrow.createJob(worker, arbiter, AMOUNT, "no allowance");
    }

    // ---- claimJob (acik is pazari) ----

    function test_ClaimJob_SetsWorkerAndEmitsEvent() public {
        uint256 jobId = _createOpenJob();

        vm.expectEmit(true, true, false, false, address(escrow));
        emit JobEscrow.JobClaimed(jobId, worker);

        vm.prank(worker);
        escrow.claimJob(jobId);

        assertEq(escrow.getJob(jobId).worker, worker);
    }

    function test_ClaimJob_ThenApproveJob_PaysNewWorker() public {
        uint256 jobId = _createOpenJob();

        vm.prank(worker);
        escrow.claimJob(jobId);

        vm.prank(employer);
        escrow.approveJob(jobId);

        assertEq(usdc.balanceOf(worker), AMOUNT);
        assertEq(uint8(escrow.getJob(jobId).status), uint8(JobEscrow.Status.Completed));
    }

    function test_ClaimJob_ThenRaiseDispute_Works() public {
        uint256 jobId = _createOpenJob();

        vm.prank(worker);
        escrow.claimJob(jobId);

        vm.prank(worker);
        escrow.raiseDispute(jobId);

        assertEq(uint8(escrow.getJob(jobId).status), uint8(JobEscrow.Status.Disputed));
    }

    function test_RevertWhen_ClaimingAlreadyClaimedJob() public {
        uint256 jobId = _createOpenJob();

        vm.prank(worker);
        escrow.claimJob(jobId);

        vm.prank(stranger);
        vm.expectRevert(JobEscrow.JobNotOpen.selector);
        escrow.claimJob(jobId);
    }

    function test_RevertWhen_ClaimingJobThatAlreadyHasAssignedWorker() public {
        uint256 jobId = _createJob(); // worker onceden atanmis, acik degil

        vm.prank(stranger);
        vm.expectRevert(JobEscrow.JobNotOpen.selector);
        escrow.claimJob(jobId);
    }

    function test_RevertWhen_ClaimingNonFundedJob() public {
        uint256 jobId = _createOpenJob();

        vm.prank(worker);
        escrow.claimJob(jobId);
        vm.prank(employer);
        escrow.approveJob(jobId);

        vm.prank(stranger);
        vm.expectRevert(JobEscrow.JobNotFunded.selector);
        escrow.claimJob(jobId);
    }

    function test_RevertWhen_EmployerClaimsOwnOpenJob() public {
        uint256 jobId = _createOpenJob();

        vm.prank(employer);
        vm.expectRevert(JobEscrow.InvalidWorker.selector);
        escrow.claimJob(jobId);
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

    // ---- raiseDispute / resolveDispute ----

    function test_RaiseDispute_BlocksEmployerCancel() public {
        uint256 jobId = _createJob();

        vm.prank(worker);
        escrow.raiseDispute(jobId);

        assertEq(uint8(escrow.getJob(jobId).status), uint8(JobEscrow.Status.Disputed));

        // Isveren artik iptal edemez - iyi niyetli calisan isciyi bu sekilde koruyoruz.
        vm.prank(employer);
        vm.expectRevert(JobEscrow.JobNotFunded.selector);
        escrow.cancelJob(jobId);
    }

    function test_RevertWhen_NonWorkerRaisesDispute() public {
        uint256 jobId = _createJob();

        vm.prank(stranger);
        vm.expectRevert(JobEscrow.NotWorker.selector);
        escrow.raiseDispute(jobId);
    }

    function test_RevertWhen_RaisingDisputeWithoutArbiter() public {
        uint256 jobId = _createJobNoArbiter();

        vm.prank(worker);
        vm.expectRevert(JobEscrow.NoArbiterSet.selector);
        escrow.raiseDispute(jobId);
    }

    function test_ResolveDispute_ReleaseToWorker() public {
        uint256 jobId = _createJob();

        vm.prank(worker);
        escrow.raiseDispute(jobId);

        vm.prank(arbiter);
        escrow.resolveDispute(jobId, true);

        JobEscrow.Job memory job = escrow.getJob(jobId);
        assertEq(uint8(job.status), uint8(JobEscrow.Status.Completed));
        assertEq(usdc.balanceOf(worker), AMOUNT);
    }

    function test_ResolveDispute_ReleaseToEmployer() public {
        uint256 jobId = _createJob();
        uint256 balanceBefore = usdc.balanceOf(employer);

        vm.prank(worker);
        escrow.raiseDispute(jobId);

        vm.prank(arbiter);
        escrow.resolveDispute(jobId, false);

        JobEscrow.Job memory job = escrow.getJob(jobId);
        assertEq(uint8(job.status), uint8(JobEscrow.Status.Cancelled));
        assertEq(usdc.balanceOf(employer), balanceBefore + AMOUNT);
    }

    function test_RevertWhen_NonArbiterResolvesDispute() public {
        uint256 jobId = _createJob();

        vm.prank(worker);
        escrow.raiseDispute(jobId);

        vm.prank(employer);
        vm.expectRevert(JobEscrow.NotArbiter.selector);
        escrow.resolveDispute(jobId, true);
    }

    function test_RevertWhen_ResolvingNonDisputedJob() public {
        uint256 jobId = _createJob();

        vm.prank(arbiter);
        vm.expectRevert(JobEscrow.JobNotDisputed.selector);
        escrow.resolveDispute(jobId, true);
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
