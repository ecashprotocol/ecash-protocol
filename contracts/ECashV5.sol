// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title eCash V5 - Production
 * @notice Proof-of-Intelligence cryptocurrency on Base
 * @dev Batch-based mining with 4 eras, per-batch burns, on-chain encrypted poems
 */
contract ECashV5 is ERC20, Ownable, ReentrancyGuard {
    // ============ Token Constants ============
    uint256 public constant TOTAL_SUPPLY = 21_000_000 * 1e18;
    uint256 public constant LP_ALLOCATION = 2_100_000 * 1e18;
    uint256 public constant MINING_RESERVE = 18_900_000 * 1e18;

    // ============ Puzzle & Batch Constants ============
    uint256 public constant TOTAL_PUZZLES = 6300;
    uint256 public constant BATCH_SIZE = 10;
    uint256 public constant ADVANCE_THRESHOLD = 8;

    // ============ Era Boundaries ============
    uint256 public constant ERA_1_END = 1575;
    uint256 public constant ERA_2_END = 3150;
    uint256 public constant ERA_3_END = 4725;
    uint256 public constant ERA_4_END = 6300;

    // ============ Era Rewards ============
    uint256 public constant ERA_1_REWARD = 6400 * 1e18;
    uint256 public constant ERA_2_REWARD = 3200 * 1e18;
    uint256 public constant ERA_3_REWARD = 1600 * 1e18;
    uint256 public constant ERA_4_REWARD = 800 * 1e18;

    // ============ Per-Batch Entry Burns ============
    uint256 public constant ERA_1_BATCH_BURN = 1000 * 1e18;
    uint256 public constant ERA_2_BATCH_BURN = 500 * 1e18;
    uint256 public constant ERA_3_BATCH_BURN = 250 * 1e18;
    uint256 public constant ERA_4_BATCH_BURN = 125 * 1e18;

    // ============ Batch Timing ============
    uint256 public constant BATCH_COOLDOWN = 30 minutes;

    // ============ Gas System ============
    uint256 public constant INITIAL_GAS = 500;
    uint256 public constant PICK_COST = 10;
    uint256 public constant COMMIT_COST = 25;
    uint256 public constant SOLVE_BONUS = 100;
    uint256 public constant GAS_FLOOR = 35;
    uint256 public constant DAILY_REGEN = 5;
    uint256 public constant GAS_CAP = 100;
    uint256 public constant REFERRAL_BONUS = 50;

    // ============ Timing Constants ============
    uint256 public constant PICK_TIMEOUT = 900; // 15 minutes
    uint256 public constant REVEAL_WINDOW = 256; // blocks
    uint256 public constant MAX_ATTEMPTS = 3;
    uint256 public constant LOCKOUT_DURATION = 86400; // 24 hours
    uint256 public constant GAS_REGEN_INTERVAL = 86400; // 24 hours
    uint256 public constant STALE_THRESHOLD = 48 hours;

    // ============ Emergency ============
    uint256 public constant INACTIVITY_THRESHOLD = 7 days;

    // ============ Immutable State ============
    bytes32 public immutable merkleRoot;
    bytes32 public immutable DATA_HASH;
    bytes32 public immutable MASTER_KEY;

    // ============ Puzzle State ============
    uint256 public totalSolved;
    mapping(uint256 => bool) public solved;
    mapping(uint256 => address) public solvedBy;

    // ============ Batch State ============
    uint256 public currentBatch;
    uint256 public batchSolveCount;
    uint256 public batchStartTimestamp;
    uint256 public lastSolveTimestamp;
    uint256 public lastBatchAdvanceTimestamp;
    mapping(uint256 => address) public batchAdvancer;

    // ============ Emergency State ============
    bool public emergencyReleased;

    // ============ User State ============
    struct UserState {
        bool registered;
        uint96 gasBalance;
        uint40 lastRegenTime;
        uint40 pickTime;
        uint24 activePick;
        bool hasPick;
        uint40 lastSolveTime;
        uint24 totalSolves;
        address referrer;
        bytes32 commitHash;
        uint64 commitBlock;
    }

    mapping(address => UserState) public users;
    mapping(address => mapping(uint256 => bool)) public batchEntries;
    mapping(address => mapping(uint256 => uint8)) public attemptCount;
    mapping(address => mapping(uint256 => uint40)) public lockoutUntil;
    mapping(address => uint256) public referralCount;

    // ============ Events ============
    event Registered(address indexed user, address indexed referrer);
    event BatchEntered(address indexed user, uint256 indexed batchId, uint256 cost);
    event PuzzlePicked(address indexed user, uint256 indexed puzzleId);
    event CommitSubmitted(address indexed user, bytes32 commitHash, uint256 blockNumber);
    event PuzzleSolved(address indexed solver, uint256 indexed puzzleId, uint256 reward);
    event BatchAdvanced(uint256 indexed newBatchId, address indexed advancer);
    event BatchPublished(uint256 indexed batchId, bytes encryptedPoems);
    event EmergencyRelease(bytes32 masterKey);
    event CommitCancelled(address indexed user, uint256 indexed puzzleId);
    event WrongAnswer(address indexed user, uint256 indexed puzzleId, uint8 attempts);
    event LockedOut(address indexed user, uint256 indexed puzzleId, uint40 until);
    event PickCleared(address indexed user, uint256 indexed puzzleId);

    // ============ Errors ============
    error AlreadyRegistered();
    error NotRegistered();
    error InvalidReferrer();
    error AlreadyEnteredBatch();
    error NotEnteredBatch();
    error InsufficientECASH();
    error InvalidPuzzleId();
    error PuzzleAlreadySolved();
    error PuzzleNotYetSolved();
    error PuzzleNotInCurrentBatch();
    error AlreadyHasPick();
    error NoActivePick();
    error PickExpired();
    error InsufficientGas();
    error AlreadyCommitted();
    error NoCommitment();
    error CommitmentExpired();
    error CommitNotExpired();
    error SameBlockReveal();
    error CommitmentMismatch();
    error MaxAttemptsReached();
    error LockedOutFromPuzzle();
    error BatchCooldownNotMet();
    error NotStaleYet();
    error EmergencyTooEarly();
    error BatchNotAvailable();

    // ============ Constructor ============
    constructor(
        bytes32 _merkleRoot,
        bytes32 _dataHash,
        bytes32 _masterKey
    ) ERC20("eCash", "ECASH") Ownable(msg.sender) {
        merkleRoot = _merkleRoot;
        DATA_HASH = _dataHash;
        MASTER_KEY = _masterKey;

        _mint(msg.sender, LP_ALLOCATION);
        _mint(address(this), MINING_RESERVE);

        batchStartTimestamp = block.timestamp;
        lastSolveTimestamp = block.timestamp;
        lastBatchAdvanceTimestamp = block.timestamp;
    }

    // ============ Owner Functions ============

    function publishEncryptedBatch(uint256 batchId, bytes calldata encryptedPoems) external onlyOwner {
        emit BatchPublished(batchId, encryptedPoems);
    }

    // ============ Registration ============

    function register(address referrer) external {
        UserState storage user = users[msg.sender];
        if (user.registered) revert AlreadyRegistered();

        user.registered = true;
        user.gasBalance = uint96(INITIAL_GAS);
        user.lastRegenTime = uint40(block.timestamp);

        if (referrer != address(0)) {
            if (referrer == msg.sender) revert InvalidReferrer();
            if (!users[referrer].registered) revert InvalidReferrer();

            user.referrer = referrer;
            users[referrer].gasBalance += uint96(REFERRAL_BONUS);
            referralCount[referrer]++;

            if (users[referrer].gasBalance > GAS_CAP * 10) {
                users[referrer].gasBalance = uint96(GAS_CAP * 10);
            }
        }

        emit Registered(msg.sender, referrer);
    }

    // ============ Batch Entry ============

    /// @notice Burn ECASH to enter current batch
    function enterBatch() external {
        UserState storage user = users[msg.sender];
        if (!user.registered) revert NotRegistered();

        uint256 batch = currentBatch;
        if (batchEntries[msg.sender][batch]) revert AlreadyEnteredBatch();

        uint256 cost = getBatchEntryCost();
        if (balanceOf(msg.sender) < cost) revert InsufficientECASH();

        _burn(msg.sender, cost);
        batchEntries[msg.sender][batch] = true;

        emit BatchEntered(msg.sender, batch, cost);
    }

    /// @notice Get the per-batch burn cost for current era
    function getBatchEntryCost() public view returns (uint256) {
        uint256 puzzleStart = currentBatch * BATCH_SIZE;
        if (puzzleStart < ERA_1_END) return ERA_1_BATCH_BURN;
        if (puzzleStart < ERA_2_END) return ERA_2_BATCH_BURN;
        if (puzzleStart < ERA_3_END) return ERA_3_BATCH_BURN;
        return ERA_4_BATCH_BURN;
    }

    // ============ Pick ============

    function pick(uint256 puzzleId) external {
        UserState storage user = users[msg.sender];
        if (!user.registered) revert NotRegistered();
        if (!batchEntries[msg.sender][currentBatch]) revert NotEnteredBatch();
        if (puzzleId >= TOTAL_PUZZLES) revert InvalidPuzzleId();
        if (solved[puzzleId]) revert PuzzleAlreadySolved();

        (uint256 batchStart, uint256 batchEnd) = getCurrentBatchRange();
        bool inCurrentBatch = puzzleId >= batchStart && puzzleId < batchEnd;
        bool inPreviousBatch = currentBatch > 0 && puzzleId < batchStart && !solved[puzzleId];

        if (!inCurrentBatch && !inPreviousBatch) revert PuzzleNotInCurrentBatch();

        if (currentBatch > 0 && inCurrentBatch) {
            _checkBatchReady();
        }

        if (user.hasPick && block.timestamp > user.pickTime + PICK_TIMEOUT) {
            emit PickCleared(msg.sender, user.activePick);
            user.hasPick = false;
        }

        if (user.hasPick) revert AlreadyHasPick();

        uint256 effectiveGas = _getEffectiveGas(msg.sender);
        if (effectiveGas < PICK_COST && effectiveGas < GAS_FLOOR) {
            revert InsufficientGas();
        }

        if (effectiveGas >= PICK_COST) {
            user.gasBalance = uint96(effectiveGas - PICK_COST);
            user.lastRegenTime = uint40(block.timestamp);
        }

        user.activePick = uint24(puzzleId);
        user.pickTime = uint40(block.timestamp);
        user.hasPick = true;

        emit PuzzlePicked(msg.sender, puzzleId);
    }

    // ============ Commit ============

    function commitSolve(bytes32 _commitHash) external {
        UserState storage user = users[msg.sender];
        if (!user.hasPick) revert NoActivePick();

        uint256 puzzleId = user.activePick;

        if (block.timestamp > user.pickTime + PICK_TIMEOUT) {
            revert PickExpired();
        }

        if (attemptCount[msg.sender][puzzleId] >= MAX_ATTEMPTS) {
            revert MaxAttemptsReached();
        }

        if (block.timestamp < lockoutUntil[msg.sender][puzzleId]) {
            revert LockedOutFromPuzzle();
        }

        if (user.commitHash != bytes32(0) && block.number > user.commitBlock + REVEAL_WINDOW) {
            user.commitHash = bytes32(0);
            user.commitBlock = 0;
        }

        if (user.commitHash != bytes32(0)) revert AlreadyCommitted();

        uint256 effectiveGas = _getEffectiveGas(msg.sender);
        if (effectiveGas < COMMIT_COST && effectiveGas < GAS_FLOOR) {
            revert InsufficientGas();
        }

        if (effectiveGas >= COMMIT_COST) {
            user.gasBalance = uint96(effectiveGas - COMMIT_COST);
            user.lastRegenTime = uint40(block.timestamp);
        }

        user.commitHash = _commitHash;
        user.commitBlock = uint64(block.number);

        emit CommitSubmitted(msg.sender, _commitHash, block.number);
    }

    // ============ Reveal ============

    function revealSolve(
        string calldata answer,
        bytes32 salt,
        bytes32 secret,
        bytes32[] calldata proof
    ) external nonReentrant {
        UserState storage user = users[msg.sender];

        if (user.commitHash == bytes32(0)) revert NoCommitment();
        if (block.number == user.commitBlock) revert SameBlockReveal();
        if (block.number > user.commitBlock + REVEAL_WINDOW) revert CommitmentExpired();

        uint256 puzzleId = user.activePick;
        if (solved[puzzleId]) revert PuzzleAlreadySolved();

        bytes32 expectedHash = keccak256(abi.encodePacked(
            _normalizeAnswer(answer),
            salt,
            secret,
            msg.sender
        ));
        if (expectedHash != user.commitHash) revert CommitmentMismatch();

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(
            puzzleId,
            _normalizeAnswer(answer),
            salt
        ))));

        if (!MerkleProof.verify(proof, merkleRoot, leaf)) {
            uint8 newAttempts = attemptCount[msg.sender][puzzleId] + 1;
            attemptCount[msg.sender][puzzleId] = newAttempts;
            user.commitHash = bytes32(0);
            user.commitBlock = 0;

            emit WrongAnswer(msg.sender, puzzleId, newAttempts);

            if (newAttempts >= MAX_ATTEMPTS) {
                lockoutUntil[msg.sender][puzzleId] = uint40(block.timestamp + LOCKOUT_DURATION);
                emit LockedOut(msg.sender, puzzleId, lockoutUntil[msg.sender][puzzleId]);
            }

            return;
        }

        solved[puzzleId] = true;
        solvedBy[puzzleId] = msg.sender;
        totalSolved++;
        batchSolveCount++;
        lastSolveTimestamp = block.timestamp;

        user.lastSolveTime = uint40(block.timestamp);
        user.totalSolves++;
        user.hasPick = false;
        user.commitHash = bytes32(0);
        user.commitBlock = 0;

        user.gasBalance += uint96(SOLVE_BONUS);
        if (user.gasBalance > GAS_CAP * 10) {
            user.gasBalance = uint96(GAS_CAP * 10);
        }

        uint256 reward = getReward(puzzleId);
        _transfer(address(this), msg.sender, reward);

        emit PuzzleSolved(msg.sender, puzzleId, reward);

        uint256 threshold = _getBatchAdvanceThreshold();
        if (batchSolveCount >= threshold) {
            _advanceBatch(msg.sender);
        }
    }

    // ============ Batch Management ============

    function _getBatchAdvanceThreshold() internal view returns (uint256) {
        (uint256 batchStart, uint256 batchEnd) = getCurrentBatchRange();
        uint256 puzzlesInBatch = batchEnd - batchStart;

        if (puzzlesInBatch >= BATCH_SIZE) {
            return ADVANCE_THRESHOLD;
        }
        return (puzzlesInBatch * 80) / 100;
    }

    function _advanceBatch(address advancer) internal {
        batchAdvancer[currentBatch] = advancer;
        currentBatch++;
        batchSolveCount = 0;
        lastBatchAdvanceTimestamp = block.timestamp;
        batchStartTimestamp = block.timestamp;

        emit BatchAdvanced(currentBatch, advancer);
    }

    function _checkBatchReady() internal view {
        if (block.timestamp < lastBatchAdvanceTimestamp + BATCH_COOLDOWN) {
            revert BatchCooldownNotMet();
        }
    }

    /// @notice Force advance a stale batch (48h no activity)
    function forceAdvanceStaleBatch() external virtual {
        if (block.timestamp <= batchStartTimestamp + STALE_THRESHOLD) {
            revert NotStaleYet();
        }

        batchAdvancer[currentBatch] = address(0);
        currentBatch++;
        batchSolveCount = 0;
        lastBatchAdvanceTimestamp = block.timestamp;
        batchStartTimestamp = block.timestamp;
        lastSolveTimestamp = block.timestamp;

        emit BatchAdvanced(currentBatch, address(0));
    }

    // ============ Emergency Release ============

    function triggerEmergencyRelease() external {
        if (block.timestamp <= lastSolveTimestamp + INACTIVITY_THRESHOLD) {
            revert EmergencyTooEarly();
        }

        emergencyReleased = true;
        emit EmergencyRelease(MASTER_KEY);
    }

    // ============ Batch Key ============

    function getBatchKey(uint256 batchId) public view returns (bytes32) {
        if (emergencyReleased) {
            return keccak256(abi.encode(MASTER_KEY, batchId));
        }

        if (batchId == 0) {
            return keccak256(abi.encode(merkleRoot, "batch0"));
        }

        if (batchId > currentBatch) revert BatchNotAvailable();

        address prevAdvancer = batchAdvancer[batchId - 1];

        if (prevAdvancer == address(0)) {
            return keccak256(abi.encode(batchId, merkleRoot, "stale"));
        }

        return keccak256(abi.encode(prevAdvancer, batchId, merkleRoot));
    }

    // ============ Utility Functions ============

    function cancelExpiredCommit() external {
        UserState storage user = users[msg.sender];
        if (user.commitHash == bytes32(0)) revert NoCommitment();
        if (block.number <= user.commitBlock + REVEAL_WINDOW) revert CommitNotExpired();

        uint256 puzzleId = user.activePick;
        user.commitHash = bytes32(0);
        user.commitBlock = 0;

        emit CommitCancelled(msg.sender, puzzleId);
    }

    function clearSolvedPick() external {
        UserState storage user = users[msg.sender];
        if (!user.hasPick) revert NoActivePick();
        if (!solved[user.activePick]) revert PuzzleNotYetSolved();

        emit PickCleared(msg.sender, user.activePick);
        user.hasPick = false;
        user.commitHash = bytes32(0);
        user.commitBlock = 0;
    }

    // ============ View Functions ============

    function getCurrentBatchRange() public view returns (uint256 start, uint256 end) {
        start = currentBatch * BATCH_SIZE;
        end = start + BATCH_SIZE;
        if (end > TOTAL_PUZZLES) end = TOTAL_PUZZLES;
    }

    function getReward(uint256 puzzleId) public pure returns (uint256) {
        if (puzzleId < ERA_1_END) return ERA_1_REWARD;
        if (puzzleId < ERA_2_END) return ERA_2_REWARD;
        if (puzzleId < ERA_3_END) return ERA_3_REWARD;
        return ERA_4_REWARD;
    }

    function getBatchCooldown() public pure returns (uint256) {
        return BATCH_COOLDOWN;
    }

    function miningReserveBalance() public view returns (uint256) {
        return balanceOf(address(this));
    }

    function getEffectiveGas(address addr) external view returns (uint256) {
        return _getEffectiveGas(addr);
    }

    function _getEffectiveGas(address addr) internal view returns (uint256) {
        UserState storage user = users[addr];
        if (!user.registered) return 0;

        uint256 gas = user.gasBalance;
        uint256 elapsed = block.timestamp - user.lastRegenTime;
        uint256 regenPeriods = elapsed / GAS_REGEN_INTERVAL;

        if (regenPeriods > 0) {
            gas += regenPeriods * DAILY_REGEN;
            if (gas > GAS_CAP * 10) gas = GAS_CAP * 10;
        }

        return gas;
    }

    function getUserState(address addr) external view returns (
        bool registered,
        uint256 gas,
        bool hasPick,
        uint256 activePick,
        uint256 pickTime,
        uint256 totalSolves_,
        uint256 lastSolveTime,
        bool hasCommit,
        uint256 commitBlock
    ) {
        UserState storage user = users[addr];
        return (
            user.registered,
            _getEffectiveGas(addr),
            user.hasPick,
            user.activePick,
            user.pickTime,
            user.totalSolves,
            user.lastSolveTime,
            user.commitHash != bytes32(0),
            user.commitBlock
        );
    }

    function getCommitment(address addr) external view returns (bytes32 hash, uint256 blockNumber) {
        UserState storage user = users[addr];
        return (user.commitHash, user.commitBlock);
    }

    function getAttemptInfo(address addr, uint256 puzzleId) external view returns (
        uint8 attempts,
        uint40 lockedUntil_,
        bool isLockedOut
    ) {
        return (
            attemptCount[addr][puzzleId],
            lockoutUntil[addr][puzzleId],
            block.timestamp < lockoutUntil[addr][puzzleId]
        );
    }

    function getBatchAdvanceThreshold() external view returns (uint256) {
        return _getBatchAdvanceThreshold();
    }

    // ============ Answer Normalization ============

    function _normalizeAnswer(string calldata answer) internal pure returns (string memory) {
        bytes memory input = bytes(answer);
        bytes memory output = new bytes(input.length);
        uint256 outputLen = 0;
        bool lastWasSpace = true;

        for (uint256 i = 0; i < input.length; i++) {
            bytes1 char = input[i];
            bytes1 c = char;

            if (uint8(char) >= 65 && uint8(char) <= 90) {
                c = bytes1(uint8(char) + 32);
            }

            bool isLower = uint8(c) >= 97 && uint8(c) <= 122;
            bool isDigit = uint8(c) >= 48 && uint8(c) <= 57;
            bool isSpace = c == 0x20;

            if (isLower || isDigit) {
                output[outputLen++] = c;
                lastWasSpace = false;
            } else if (isSpace && !lastWasSpace) {
                output[outputLen++] = c;
                lastWasSpace = true;
            }
        }

        if (outputLen > 0 && output[outputLen - 1] == 0x20) {
            outputLen--;
        }

        bytes memory result = new bytes(outputLen);
        for (uint256 i = 0; i < outputLen; i++) {
            result[i] = output[i];
        }

        return string(result);
    }
}

