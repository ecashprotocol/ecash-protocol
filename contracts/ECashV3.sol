// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title eCash Protocol V3.2
 * @notice Mine crypto by solving riddles. 6,300 puzzles. Two eras. One chance per puzzle.
 * @dev Commit-reveal scheme prevents front-running. Per-puzzle salts prevent rainbow tables.
 */
contract ECashV3 is ERC20, ReentrancyGuard {
    // ============ Constants ============
    uint256 public constant TOTAL_PUZZLES = 6300;
    uint256 public constant ERA_1_END = 3149;
    uint256 public constant ERA_1_REWARD = 4000 ether;
    uint256 public constant ERA_2_REWARD = 2000 ether;
    uint256 public constant TOTAL_SUPPLY = 21_000_000 ether;
    uint256 public constant LP_ALLOCATION = 2_100_000 ether;
    uint256 public constant MINING_RESERVE = 18_900_000 ether;

    // Gas system constants
    uint256 public constant INITIAL_GAS = 500;
    uint256 public constant GAS_FLOOR = 35;
    uint256 public constant GAS_CAP = 100;
    uint256 public constant GAS_REGEN_RATE = 5;
    uint256 public constant GAS_REGEN_INTERVAL = 1 days;
    uint256 public constant PICK_COST = 10;
    uint256 public constant COMMIT_COST = 25;
    uint256 public constant REFERRAL_BONUS = 50;
    uint256 public constant SOLVE_BONUS = 100;

    // Attempt/lockout constants
    uint256 public constant MAX_ATTEMPTS = 3;
    uint256 public constant LOCKOUT_DURATION = 24 hours;
    uint256 public constant SOLVE_COOLDOWN = 5 minutes;

    // Timing constants
    uint256 public constant PICK_TIMEOUT = 24 hours;
    uint256 public constant REVEAL_WINDOW = 256;

    // ============ Immutable State ============
    bytes32 public immutable merkleRoot;

    // ============ Ownership ============
    address public owner;
    bool public ownershipRenounced;

    // ============ User State ============
    struct UserState {
        bool registered;
        uint96 gasBalance;
        uint40 lastRegenTime;
        uint40 pickTime;
        uint24 activePick;
        bool hasPick;
        uint16 streak;
        uint40 lastSolveTime;
        uint24 totalSolves;
        address referrer;
    }
    mapping(address => UserState) public users;
    mapping(address => uint256) public referralCount;

    // ============ Puzzle State ============
    mapping(uint256 => bool) public puzzleSolved;
    mapping(uint256 => address) public puzzleSolver;
    uint256 public totalSolved;

    // ============ Attempt Tracking ============
    mapping(address => mapping(uint256 => uint8)) public attemptCount;
    mapping(address => mapping(uint256 => uint40)) public lockoutUntil;

    // ============ Commit-Reveal State ============
    struct Commitment {
        bytes32 hash;
        uint64 blockNumber;
    }
    mapping(address => Commitment) public commitments;

    // ============ Events ============
    event Registered(address indexed user, address indexed referrer);
    event PuzzlePicked(address indexed user, uint256 indexed puzzleId);
    event CommitSubmitted(address indexed user, bytes32 commitHash, uint256 blockNumber);
    event PuzzleSolved(address indexed solver, uint256 indexed puzzleId, uint256 reward);
    event WrongAnswer(address indexed user, uint256 indexed puzzleId, uint8 attempts);
    event LockedOut(address indexed user, uint256 indexed puzzleId, uint40 until);
    event GasClaimed(address indexed user, uint256 amount);
    event OwnershipRenounced(address indexed previousOwner);
    event CommitCancelled(address indexed user, uint256 indexed puzzleId);

    // ============ Errors ============
    error NotOwner();
    error OwnershipAlreadyRenounced();
    error NotRegistered();
    error AlreadyRegistered();
    error InvalidPuzzleId();
    error PuzzleAlreadySolved();
    error InsufficientGas();
    error NoActivePick();
    error AlreadyHasPick();
    error NoCommitment();
    error CommitmentExpired();
    error SameBlockReveal();
    error CommitmentMismatch();
    error InvalidProof();
    error PickExpired();
    error AlreadyCommitted();
    error RegenNotReady();
    error LockedOutFromPuzzle();
    error SolveCooldownActive();
    error CommitNotExpired();

    // ============ Modifiers ============
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyRegistered() {
        if (!users[msg.sender].registered) revert NotRegistered();
        _;
    }

    // ============ Constructor ============
    constructor(bytes32 _merkleRoot) ERC20("eCash", "ECASH") {
        merkleRoot = _merkleRoot;
        owner = msg.sender;

        _mint(msg.sender, LP_ALLOCATION);
        _mint(address(this), MINING_RESERVE);
    }

    // ============ Registration ============
    function register(address ref) external {
        UserState storage user = users[msg.sender];
        if (user.registered) revert AlreadyRegistered();

        user.registered = true;
        user.gasBalance = uint96(INITIAL_GAS);
        user.lastRegenTime = uint40(block.timestamp);

        address validRef = address(0);
        if (ref != address(0) && ref != msg.sender && users[ref].registered) {
            user.referrer = ref;
            referralCount[ref]++;
            users[ref].gasBalance += uint96(REFERRAL_BONUS);
            validRef = ref;
        }

        emit Registered(msg.sender, validRef);
    }

    // ============ Gas System ============
    function _applyRegen(UserState storage user) internal {
        if (user.lastRegenTime == 0) return;

        uint256 elapsed = block.timestamp - user.lastRegenTime;
        uint256 intervals = elapsed / GAS_REGEN_INTERVAL;

        if (intervals > 0 && user.gasBalance < GAS_FLOOR) {
            uint256 regen = intervals * GAS_REGEN_RATE;
            uint256 newGas = user.gasBalance + regen;
            user.gasBalance = uint96(newGas > GAS_CAP ? GAS_CAP : newGas);
            user.lastRegenTime = uint40(block.timestamp);
        }
    }

    function _spendGas(UserState storage user, uint256 amount, bool allowFloorBypass) internal {
        _applyRegen(user);

        if (allowFloorBypass) {
            // Floor bypass: if at or below floor, allow action without spending
            if (user.gasBalance <= GAS_FLOOR) {
                return; // No gas spent, action allowed
            }
            // Above floor: spend but don't go below floor
            uint256 newBalance = user.gasBalance > amount ? user.gasBalance - amount : GAS_FLOOR;
            if (newBalance < GAS_FLOOR) newBalance = GAS_FLOOR;
            user.gasBalance = uint96(newBalance);
        } else {
            // No bypass: must have enough gas
            if (user.gasBalance < amount) revert InsufficientGas();
            user.gasBalance -= uint96(amount);
        }
    }

    function claimDailyGas() external onlyRegistered {
        UserState storage user = users[msg.sender];

        uint256 elapsed = block.timestamp - user.lastRegenTime;
        if (elapsed < GAS_REGEN_INTERVAL) revert RegenNotReady();

        // Only regen if below cap
        if (user.gasBalance >= GAS_CAP) {
            user.lastRegenTime = uint40(block.timestamp);
            emit GasClaimed(msg.sender, 0);
            return;
        }

        uint256 intervals = elapsed / GAS_REGEN_INTERVAL;
        uint256 regen = intervals * GAS_REGEN_RATE;
        uint256 newGas = user.gasBalance + regen;

        if (newGas > GAS_CAP) newGas = GAS_CAP;

        uint256 gained = newGas - user.gasBalance;
        user.gasBalance = uint96(newGas);
        user.lastRegenTime = uint40(block.timestamp);

        emit GasClaimed(msg.sender, gained);
    }

    function getEffectiveGas(address addr) public view returns (uint256) {
        UserState storage user = users[addr];
        if (user.lastRegenTime == 0) return user.gasBalance;

        uint256 elapsed = block.timestamp - user.lastRegenTime;
        uint256 intervals = elapsed / GAS_REGEN_INTERVAL;

        if (intervals > 0 && user.gasBalance < GAS_FLOOR) {
            uint256 regen = intervals * GAS_REGEN_RATE;
            uint256 newGas = user.gasBalance + regen;
            return newGas > GAS_CAP ? GAS_CAP : newGas;
        }

        return user.gasBalance;
    }

    // ============ Puzzle Mechanics ============
    function pick(uint256 puzzleId) external onlyRegistered nonReentrant {
        if (puzzleId >= TOTAL_PUZZLES) revert InvalidPuzzleId();
        if (puzzleSolved[puzzleId]) revert PuzzleAlreadySolved();

        // Check lockout
        if (block.timestamp < lockoutUntil[msg.sender][puzzleId]) revert LockedOutFromPuzzle();

        UserState storage user = users[msg.sender];

        // Check if user has an expired pick (allow re-pick)
        if (user.hasPick) {
            if (block.timestamp < user.pickTime + PICK_TIMEOUT) {
                revert AlreadyHasPick();
            }
        }

        // Gas floor bypass: users at floor can still pick
        _spendGas(user, PICK_COST, true);

        user.activePick = uint24(puzzleId);
        user.pickTime = uint40(block.timestamp);
        user.hasPick = true;

        // Clear any existing commitment
        delete commitments[msg.sender];

        emit PuzzlePicked(msg.sender, puzzleId);
    }

    function commitSolve(bytes32 hash) external onlyRegistered nonReentrant {
        UserState storage user = users[msg.sender];

        if (!user.hasPick) revert NoActivePick();
        if (block.timestamp >= user.pickTime + PICK_TIMEOUT) revert PickExpired();

        // ============ THE FIX: Auto-clear expired commit ============
        Commitment storage commitment = commitments[msg.sender];
        if (commitment.hash != bytes32(0) && block.number > commitment.blockNumber + REVEAL_WINDOW) {
            commitment.hash = bytes32(0);
            commitment.blockNumber = 0;
        }
        // ============ END FIX ============

        if (commitment.hash != bytes32(0)) revert AlreadyCommitted();

        // Check lockout on current puzzle
        uint256 puzzleId = user.activePick;
        if (block.timestamp < lockoutUntil[msg.sender][puzzleId]) revert LockedOutFromPuzzle();

        // Gas floor bypass: users at floor can still commit
        _spendGas(user, COMMIT_COST, true);

        commitment.hash = hash;
        commitment.blockNumber = uint64(block.number);

        emit CommitSubmitted(msg.sender, hash, block.number);
    }

    function cancelExpiredCommit() external onlyRegistered {
        UserState storage user = users[msg.sender];
        Commitment storage commitment = commitments[msg.sender];

        if (!user.hasPick) revert NoActivePick();
        if (commitment.hash == bytes32(0)) revert NoCommitment();
        if (block.number <= commitment.blockNumber + REVEAL_WINDOW) revert CommitNotExpired();

        uint256 puzzleId = user.activePick;

        commitment.hash = bytes32(0);
        commitment.blockNumber = 0;

        emit CommitCancelled(msg.sender, puzzleId);
    }

    function revealSolve(
        string calldata answer,
        bytes32 salt,
        bytes32 secret,
        bytes32[] calldata proof
    ) external onlyRegistered nonReentrant {
        UserState storage user = users[msg.sender];
        Commitment storage commitment = commitments[msg.sender];

        if (!user.hasPick) revert NoActivePick();
        if (commitment.hash == bytes32(0)) revert NoCommitment();

        // Same-block reveal protection: must be strictly greater
        if (block.number <= commitment.blockNumber) revert SameBlockReveal();

        // Check reveal window (256 blocks)
        if (block.number > commitment.blockNumber + REVEAL_WINDOW) revert CommitmentExpired();

        uint256 puzzleId = user.activePick;
        if (puzzleSolved[puzzleId]) revert PuzzleAlreadySolved();

        // Check lockout
        if (block.timestamp < lockoutUntil[msg.sender][puzzleId]) revert LockedOutFromPuzzle();

        // Verify commitment: keccak256(abi.encodePacked(answer, salt, secret, msg.sender))
        // msg.sender binding prevents front-running. Salt is per-puzzle so puzzleId is implicit.
        bytes32 expectedCommit = keccak256(abi.encodePacked(answer, salt, secret, msg.sender));
        if (commitment.hash != expectedCommit) revert CommitmentMismatch();

        // Normalize answer for merkle verification
        string memory normalizedAnswer = _normalizeAnswer(answer);

        // Verify merkle proof: double-hashed leaf
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(puzzleId, normalizedAnswer, salt))));

        if (!MerkleProof.verify(proof, merkleRoot, leaf)) {
            _handleWrongAnswer(user, puzzleId);
            return;
        }

        // Check solve cooldown
        if (user.lastSolveTime > 0 && block.timestamp < user.lastSolveTime + SOLVE_COOLDOWN) {
            revert SolveCooldownActive();
        }

        _completeSolve(user, puzzleId);
    }

    function _normalizeAnswer(string calldata answer) internal pure returns (string memory) {
        bytes memory input = bytes(answer);
        bytes memory output = new bytes(input.length);
        uint256 outputLen = 0;
        bool lastWasSpace = true;

        for (uint256 i = 0; i < input.length; i++) {
            bytes1 char = input[i];

            // Convert uppercase to lowercase (A-Z -> a-z)
            if (char >= 0x41 && char <= 0x5A) {
                char = bytes1(uint8(char) + 32);
            }

            bool isLower = (char >= 0x61 && char <= 0x7A);
            bool isDigit = (char >= 0x30 && char <= 0x39);
            bool isSpace = (char == 0x20);

            if (isLower || isDigit) {
                output[outputLen++] = char;
                lastWasSpace = false;
            } else if (isSpace && !lastWasSpace) {
                output[outputLen++] = char;
                lastWasSpace = true;
            }
            // All other characters (punctuation) are stripped
        }

        // Remove trailing space
        if (outputLen > 0 && output[outputLen - 1] == 0x20) {
            outputLen--;
        }

        bytes memory result = new bytes(outputLen);
        for (uint256 i = 0; i < outputLen; i++) {
            result[i] = output[i];
        }

        return string(result);
    }

    function _completeSolve(UserState storage user, uint256 puzzleId) internal {
        puzzleSolved[puzzleId] = true;
        puzzleSolver[puzzleId] = msg.sender;
        totalSolved++;

        // Calculate era-based reward
        uint256 reward = puzzleId <= ERA_1_END ? ERA_1_REWARD : ERA_2_REWARD;

        // Award solve bonus gas
        user.gasBalance += uint96(SOLVE_BONUS);

        // Transfer reward from contract
        _transfer(address(this), msg.sender, reward);

        // Update streak
        if (user.lastSolveTime > 0 && block.timestamp - user.lastSolveTime <= 1 days) {
            user.streak++;
            if (user.streak == 3) user.gasBalance += 10;
            else if (user.streak == 7) user.gasBalance += 25;
            else if (user.streak == 30) user.gasBalance += 100;
        } else {
            user.streak = 1;
        }

        user.lastSolveTime = uint40(block.timestamp);
        user.totalSolves++;

        // Clear pick state and attempt count
        user.hasPick = false;
        user.activePick = 0;
        user.pickTime = 0;
        delete commitments[msg.sender];
        delete attemptCount[msg.sender][puzzleId];

        emit PuzzleSolved(msg.sender, puzzleId, reward);
    }

    function _handleWrongAnswer(UserState storage user, uint256 puzzleId) internal {
        // Increment attempt count
        uint8 attempts = attemptCount[msg.sender][puzzleId] + 1;
        attemptCount[msg.sender][puzzleId] = attempts;

        // Clear commitment but keep pick (can retry if not locked out)
        delete commitments[msg.sender];

        // Reset streak
        user.streak = 0;

        emit WrongAnswer(msg.sender, puzzleId, attempts);

        // Lock out after MAX_ATTEMPTS
        if (attempts >= MAX_ATTEMPTS) {
            uint40 lockoutEnd = uint40(block.timestamp + LOCKOUT_DURATION);
            lockoutUntil[msg.sender][puzzleId] = lockoutEnd;

            // Clear pick state on lockout
            user.hasPick = false;
            user.activePick = 0;
            user.pickTime = 0;

            emit LockedOut(msg.sender, puzzleId, lockoutEnd);
        }
    }

    // ============ View Functions ============
    function getReward(uint256 puzzleId) public pure returns (uint256) {
        if (puzzleId <= ERA_1_END) {
            return ERA_1_REWARD;
        }
        return ERA_2_REWARD;
    }

    function getUserState(address addr) external view returns (
        bool registered,
        uint256 gas,
        bool hasPick,
        uint256 activePick,
        uint256 pickTime,
        uint256 streak,
        uint256 lastSolveTime,
        uint256 totalSolves
    ) {
        UserState storage user = users[addr];
        return (
            user.registered,
            getEffectiveGas(addr),
            user.hasPick,
            user.activePick,
            user.pickTime,
            user.streak,
            user.lastSolveTime,
            user.totalSolves
        );
    }

    function getCommitment(address addr) external view returns (bytes32 hash, uint256 blockNumber) {
        Commitment storage c = commitments[addr];
        return (c.hash, c.blockNumber);
    }

    function getAttemptInfo(address addr, uint256 puzzleId) external view returns (
        uint8 attempts,
        uint40 lockedUntil,
        bool isLockedOut
    ) {
        return (
            attemptCount[addr][puzzleId],
            lockoutUntil[addr][puzzleId],
            block.timestamp < lockoutUntil[addr][puzzleId]
        );
    }

    function miningReserveBalance() external view returns (uint256) {
        return balanceOf(address(this));
    }

    // ============ Owner Functions ============
    function renounceOwnership() external onlyOwner {
        if (ownershipRenounced) revert OwnershipAlreadyRenounced();

        ownershipRenounced = true;
        address oldOwner = owner;
        owner = address(0);

        emit OwnershipRenounced(oldOwner);
    }
}
