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
///
/// Guven modeli: Onay ("approveJob") ve iptal ("cancelJob") tamamen isverenin elinde -
/// bu, kotu niyetli bir isverenin isi yaptirip sonra iptal ederek isciyi magdur etmesine
/// acik kapi birakir. Bunu azaltmak icin her job'a opsiyonel bir "arbiter" (hakem) atanabilir:
/// isci, isveren onaylamayip haksiz davranirsa "raiseDispute" ile anlasmazlik acabilir,
/// bu noktadan sonra isveren artik iptal edemez - sadece hakem "resolveDispute" ile
/// parayi isciye ya da isverene yonlendirebilir.
contract JobEscrow is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Bir isin yasam dongusundeki durumlar.
    enum Status {
        None, // jobId hic olusturulmamis
        Funded, // isveren USDC'yi kilitledi, is devam ediyor
        Completed, // isveren onayladi ya da hakem isciye yonlendirdi, USDC isciye gitti
        Cancelled, // isveren iptal etti ya da hakem isverene yonlendirdi, USDC isverene dondu
        Disputed // isci anlasmazlik acti, sadece hakem cozebilir
    }

    struct Job {
        address employer; // isi olusturan ve USDC'yi kilitleyen adres
        address worker; // isi tamamlayacak ve onay sonrasi USDC alacak adres
        address arbiter; // anlasmazlik durumunda karar verecek tarafsiz adres (address(0) = hakem yok)
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
        uint256 indexed jobId,
        address indexed employer,
        address indexed worker,
        address arbiter,
        uint256 amount,
        string description
    );
    event JobApproved(uint256 indexed jobId, address indexed employer, address indexed worker, uint256 amount);
    event JobCancelled(uint256 indexed jobId, address indexed employer, uint256 amount);
    event DisputeRaised(uint256 indexed jobId, address indexed worker);
    event DisputeResolved(uint256 indexed jobId, address indexed arbiter, bool releasedToWorker);

    error InvalidWorker();
    error InvalidArbiter();
    error InvalidAmount();
    error JobNotFunded();
    error JobNotDisputed();
    error NotEmployer();
    error NotWorker();
    error NotArbiter();
    error NoArbiterSet();

    constructor(address usdcAddress) {
        if (usdcAddress == address(0)) revert InvalidWorker();
        USDC = IERC20(usdcAddress);
    }

    /// @notice Yeni bir is olusturur ve USDC'yi bu kontrata kilitler.
    /// @dev Cagirmadan once isveren, bu kontrata en az `amount` kadar USDC harcama izni
    ///      (approve) vermis olmali. Kontrat `transferFrom` ile parayi kendi bakiyesine cekiyor.
    /// @param worker Is tamamlaninca USDC'yi alacak ajan/isci cuzdani.
    /// @param arbiter Anlasmazlik durumunda karar verecek tarafsiz adres. address(0) verilirse
    ///        hakem atanmamis olur (isci bu job icin "raiseDispute" cagiramaz).
    /// @param amount Kilitlenecek USDC miktari (USDC'nin 6 decimal birimiyle, ornegin 5 USDC = 5_000_000).
    /// @param description Isin kisa aciklamasi.
    /// @return jobId Yeni olusturulan isin kimligi.
    function createJob(address worker, address arbiter, uint256 amount, string calldata description)
        external
        nonReentrant
        returns (uint256 jobId)
    {
        if (worker == address(0) || worker == msg.sender) revert InvalidWorker();
        if (arbiter == msg.sender || arbiter == worker) revert InvalidArbiter();
        if (amount == 0) revert InvalidAmount();

        jobId = jobCount++;
        jobs[jobId] = Job({
            employer: msg.sender,
            worker: worker,
            arbiter: arbiter,
            amount: amount,
            status: Status.Funded,
            description: description
        });

        USDC.safeTransferFrom(msg.sender, address(this), amount);

        emit JobCreated(jobId, msg.sender, worker, arbiter, amount, description);
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

    /// @notice Isveren, henuz onaylanmamis ve anlasmazlik acilmamis bir isi iptal eder;
    ///         kilitli USDC isverene geri doner.
    /// @dev Sadece isin sahibi (employer) cagirabilir ve is hala "Funded" durumunda olmalidir.
    ///      Is "Disputed" durumuna gectiyse artik iptal edilemez - sadece hakem karar verebilir.
    function cancelJob(uint256 jobId) external nonReentrant {
        Job storage job = jobs[jobId];
        if (job.status != Status.Funded) revert JobNotFunded();
        if (msg.sender != job.employer) revert NotEmployer();

        job.status = Status.Cancelled;
        USDC.safeTransfer(job.employer, job.amount);

        emit JobCancelled(jobId, job.employer, job.amount);
    }

    /// @notice Isci, isveren haksiz davranip onaylamiyor/iptal etmek istiyorsa anlasmazlik acar.
    /// @dev Sadece isin iscisi cagirabilir, is "Funded" durumunda olmali ve job'a bir hakem
    ///      atanmis olmali. Bu noktadan sonra isveren artik "cancelJob" cagiramaz.
    function raiseDispute(uint256 jobId) external {
        Job storage job = jobs[jobId];
        if (job.status != Status.Funded) revert JobNotFunded();
        if (msg.sender != job.worker) revert NotWorker();
        if (job.arbiter == address(0)) revert NoArbiterSet();

        job.status = Status.Disputed;

        emit DisputeRaised(jobId, msg.sender);
    }

    /// @notice Hakem, acilmis bir anlasmazligi cozer: parayi isciye ya da isverene yonlendirir.
    /// @dev Sadece job'a atanmis hakem cagirabilir, is "Disputed" durumunda olmalidir.
    /// @param releaseToWorker true ise USDC isciye gonderilir (is Completed olur),
    ///        false ise USDC isverene iade edilir (is Cancelled olur).
    function resolveDispute(uint256 jobId, bool releaseToWorker) external nonReentrant {
        Job storage job = jobs[jobId];
        if (job.status != Status.Disputed) revert JobNotDisputed();
        if (msg.sender != job.arbiter) revert NotArbiter();

        if (releaseToWorker) {
            job.status = Status.Completed;
            USDC.safeTransfer(job.worker, job.amount);
        } else {
            job.status = Status.Cancelled;
            USDC.safeTransfer(job.employer, job.amount);
        }

        emit DisputeResolved(jobId, msg.sender, releaseToWorker);
    }

    /// @notice Bir isin tum detaylarini okur.
    function getJob(uint256 jobId) external view returns (Job memory) {
        return jobs[jobId];
    }
}
