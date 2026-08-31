// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title JobEscrow
/// @notice Arc Testnet uzerinde AI ajanlari / iscilerle isverenler arasinda basit bir
///         USDC emanet (escrow) sistemi. Isveren bir ise USDC kilitler, is tamamlaninca
///         onayla parayi isciye serbest birakir, ya da tamamlanmadan iptal edip
///         parasini geri alabilir.
/// @dev Tek bir kontrat, coklu "job" (is) yonetir. Her job bagimsiz bir jobId ile takip edilir.
contract JobEscrow is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Bir isin yasam dongusundeki durumlar.
    enum Status {
        None, // jobId hic olusturulmamis
        Funded, // isveren USDC'yi kilitledi, is devam ediyor
        Completed, // isveren onayladi, USDC isciye gitti
        Cancelled // isveren onaydan once iptal etti, USDC isverene geri dondu

    }

    struct Job {
        address employer; // isi olusturan ve USDC'yi kilitleyen adres
        address worker; // isi tamamlayacak ve onay sonrasi USDC alacak adres
        uint256 amount; // kilitlenen USDC miktari (USDC ERC-20 arayuzu 6 decimal kullanir)
        Status status;
        string description; // isin kisa aciklamasi / referansi
    }

    /// @notice Arc Testnet USDC ERC-20 arayuzu (0x3600...0000), 6 decimal.
    IERC20 public immutable USDC;

    /// @notice Toplam olusturulan job sayisi; bir sonraki jobId olarak da kullanilir.
    uint256 public jobCount;

    mapping(uint256 => Job) public jobs;

    event JobCreated(
        uint256 indexed jobId, address indexed employer, address indexed worker, uint256 amount, string description
    );
    event JobApproved(uint256 indexed jobId, address indexed employer, address indexed worker, uint256 amount);
    event JobCancelled(uint256 indexed jobId, address indexed employer, uint256 amount);

    error InvalidWorker();
    error InvalidAmount();
    error JobNotFunded();
    error NotEmployer();

    constructor(address usdcAddress) {
        if (usdcAddress == address(0)) revert InvalidWorker();
        USDC = IERC20(usdcAddress);
    }

    /// @notice Yeni bir is olusturur ve USDC'yi bu kontrata kilitler.
    /// @dev Cagirmadan once isveren, bu kontrata en az `amount` kadar USDC harcama izni
    ///      (approve) vermis olmali. Kontrat `transferFrom` ile parayi kendi bakiyesine cekiyor.
    /// @param worker Is tamamlaninca USDC'yi alacak ajan/isci cuzdani.
    /// @param amount Kilitlenecek USDC miktari (USDC'nin 6 decimal birimiyle, ornegin 5 USDC = 5_000_000).
    /// @param description Isin kisa aciklamasi.
    /// @return jobId Yeni olusturulan isin kimligi.
    function createJob(address worker, uint256 amount, string calldata description)
        external
        nonReentrant
        returns (uint256 jobId)
    {
        if (worker == address(0) || worker == msg.sender) revert InvalidWorker();
        if (amount == 0) revert InvalidAmount();

        jobId = jobCount++;
        jobs[jobId] =
            Job({employer: msg.sender, worker: worker, amount: amount, status: Status.Funded, description: description});

        USDC.safeTransferFrom(msg.sender, address(this), amount);

        emit JobCreated(jobId, msg.sender, worker, amount, description);
    }

    /// @notice Isveren isi onaylar; kilitli USDC isciye gonderilir.
    /// @dev Sadece isin sahibi (employer) cagirabilir ve is hala "Funded" durumunda olmalidir.
    function approveJob(uint256 jobId) external nonReentrant {
        Job storage job = jobs[jobId];
        if (job.status != Status.Funded) revert JobNotFunded();
        if (msg.sender != job.employer) revert NotEmployer();

        job.status = Status.Completed;
        USDC.safeTransfer(job.worker, job.amount);

        emit JobApproved(jobId, job.employer, job.worker, job.amount);
    }

    /// @notice Isveren, henuz onaylanmamis bir isi iptal eder; kilitli USDC isverene geri doner.
    /// @dev Sadece isin sahibi (employer) cagirabilir ve is hala "Funded" durumunda olmalidir.
    function cancelJob(uint256 jobId) external nonReentrant {
        Job storage job = jobs[jobId];
        if (job.status != Status.Funded) revert JobNotFunded();
        if (msg.sender != job.employer) revert NotEmployer();

        job.status = Status.Cancelled;
        USDC.safeTransfer(job.employer, job.amount);

        emit JobCancelled(jobId, job.employer, job.amount);
    }

    /// @notice Bir isin tum detaylarini okur.
    function getJob(uint256 jobId) external view returns (Job memory) {
        return jobs[jobId];
    }
}
