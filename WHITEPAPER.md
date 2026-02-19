# eCash Protocol: Proof-of-Intelligence Mining on Base

**Version 1.0 — February 2026**

**Abstract.** eCash introduces a novel token distribution mechanism called Proof-of-Intelligence — a cryptographic mining protocol where ERC-20 tokens are earned exclusively by solving encrypted riddle-poems. Unlike Proof-of-Work (which rewards computational brute force) or Proof-of-Stake (which rewards capital), Proof-of-Intelligence rewards cognitive reasoning. The protocol deploys 6,300 puzzles as scrypt-encrypted blobs on IPFS, uses a commit-reveal scheme with merkle proof verification on Base L2, and achieves full trustlessness through an architecture where no server, operator, or authority controls any aspect of token distribution. Every token in existence was earned by solving a puzzle. There is no premine, no team allocation, no venture funding, and no admin keys. After ownership renunciation, the protocol is fully immutable.

---

## 1. Introduction

### 1.1 The Problem with Token Distribution

The cryptocurrency industry has a distribution problem. The vast majority of tokens are distributed through mechanisms that concentrate wealth in the hands of insiders: presales, team allocations, venture rounds, airdrops to early addresses, and inflationary staking rewards. Even "fair launch" tokens typically involve a deployer who controls minting, pausing, or upgrading.

Bitcoin solved this elegantly: every BTC that exists was mined by expending computational energy. But Bitcoin mining has become industrialized — requiring millions of dollars in ASIC hardware and consuming more electricity than many nations.

### 1.2 A New Approach

eCash proposes an alternative: **Proof-of-Intelligence mining.** Instead of burning electricity, miners expend cognitive effort — solving cryptographic riddle-poems that require reasoning across 14 crypto/web3 knowledge domains. The protocol is designed so that:

- **Every token is earned.** 90% of supply (18.9M ECASH) sits in a mining reserve, released only when puzzles are solved. 10% (2.1M) provides initial DEX liquidity.
- **Anyone can mine.** Cost to start: ~$0.01 in ETH gas on Base L2. No hardware. No staking. No permission.
- **AI agents can mine autonomously.** The protocol is specifically designed for machine intelligence — agents install a skill file, read poems, reason about answers, and claim rewards without human intervention.
- **The protocol is fully trustless.** All puzzle data is on IPFS. Verification happens locally via scrypt. The smart contract is immutable. No server is required.

### 1.3 The Bitcoin Parallel

| Property | Bitcoin | eCash |
|---|---|---|
| Total Supply | 21,000,000 BTC | 21,000,000 ECASH |
| Mining Mechanism | SHA-256 hash puzzles | scrypt-encrypted riddle-poems |
| Halving | Every 210,000 blocks | After puzzle 3,149 |
| Team Allocation | 0% | 0% |
| Presale | None | None |
| Immutability | Consensus rules | Ownership renounced |
| Hardware Required | $10,000+ ASICs | A reasoning mind (or AI agent) |
| Cost to Start | Thousands of dollars | $0.01 in gas |
| Data Availability | Full blockchain replication | IPFS replication |
| Verification | Anyone can run a full node | Anyone can run scrypt locally |

---

## 2. Protocol Architecture

### 2.1 System Overview

The eCash protocol consists of four layers:

```
┌──────────────────────────────────────────────┐
│              PUZZLE LAYER (IPFS)              │
│                                              │
│  6,300 riddle-poems (public)                 │
│  6,300 scrypt-encrypted blobs (public)       │
│  No secrets. No API keys. No gatekeepers.    │
└──────────────────┬───────────────────────────┘
                   │
      ┌────────────┼────────────┐
      │            │            │
      ▼            ▼            ▼
┌──────────┐ ┌─────────┐ ┌──────────┐
│ Your Bot │ │ Web UI  │ │ Any API  │
│ (local)  │ │         │ │ (anyone  │
│          │ │         │ │ can run) │
└────┬─────┘ └────┬────┘ └────┬─────┘
     │            │           │
     │   scrypt(guess) = key  │
     │   AES-GCM decrypt blob │
     │   success → salt+proof │
     │            │           │
     └────────────┼───────────┘
                  │
                  ▼
┌──────────────────────────────────────────────┐
│           CONSENSUS LAYER (Base L2)          │
│                                              │
│  register → pick → commit → reveal          │
│  Merkle proof verification                   │
│  ECASH minted to solver                      │
│  Immutable. No admin. No upgrade.            │
└──────────────────────────────────────────────┘
```

**Layer 1 — Puzzle Data (IPFS):** All 6,300 riddle-poems and their corresponding scrypt-encrypted verification blobs are stored on IPFS. This data is public, immutable, and permanently available. Anyone can download the full dataset and mine offline.

**Layer 2 — Verification (Local):** Miners verify their guesses locally using scrypt key derivation + AES-256-GCM decryption. This is computationally expensive (~270ms, 128MB RAM per guess) but free in terms of gas. Wrong guesses never touch the blockchain.

**Layer 3 — Claiming (Base L2):** When a miner has a verified correct answer, they claim their reward on-chain using a commit-reveal scheme with merkle proof verification. The smart contract mints ECASH directly to the solver's wallet.

**Layer 4 — Trading (Aerodrome DEX):** ECASH is a standard ERC-20 token. When holders choose to sell, they can trade on Aerodrome, Base's largest decentralized exchange.

### 2.2 Key Design Principle: Anyone Can Run Everything

The reference API at api.ecash.bot is a convenience layer. It serves the same public data anyone can download from IPFS. It runs the same scrypt verification anyone can run locally. It holds zero secrets.

If the API disappears, the protocol continues. If the website disappears, the protocol continues. If the creator disappears, the protocol continues. The only thing that matters is the smart contract on Base and the data on IPFS — both of which are immutable and replicated.

---

## 3. Cryptographic Design

### 3.1 Three Layers of Protection

eCash uses three independent cryptographic mechanisms, each protecting against a different attack vector:

#### 3.1.1 scrypt — Brute-Force Resistance

Each puzzle answer is used as the password for an scrypt key derivation, which produces the decryption key for an AES-256-GCM encrypted blob. The scrypt parameters are intentionally expensive:

```
N = 131,072 (2^17)    — CPU/memory cost
r = 8                  — block size parameter
p = 1                  — parallelization parameter
keyLen = 32 bytes      — AES-256 key length
Salt = "ecash-v3-{puzzleId}" — domain separation
```

**Per-guess cost:**
- CPU time: ~270ms on modern hardware
- Memory: 128MB (128 × N × r × p bytes)
- Cannot be efficiently parallelized on GPUs (memory-bound, not compute-bound)

**Brute-force economics:** Answers are 3+ words drawn from a vocabulary spanning 14 crypto/web3 knowledge domains. With a conservative dictionary of 10,000 relevant terms, three-word combinations yield 10^12 possibilities. At 270ms per guess, a single machine needs 8,561 years per puzzle. Even 10,000 machines running in parallel need 312 days per puzzle — and there are 6,300 puzzles.

This makes brute-forcing economically irrational. The cost of cloud compute far exceeds the value of the tokens.

#### 3.1.2 Commit-Reveal — Front-Running Protection

When a miner submits their answer on-chain, it happens in two transactions across different blocks:

**Commit transaction:**
```
commitHash = keccak256(
  abi.encodePacked(
    answer,            ← the normalized answer
    salt,              ← puzzle-specific salt (from decrypted blob)
    secret,            ← random bytes32 (anti-rainbow)
    msg.sender         ← solver's address (anti-theft)
  )
)
contract.commitSolve(commitHash)
```

**Reveal transaction (different block):**
```
contract.revealSolve(answer, salt, secret, proof)
```

The commit hash includes `msg.sender`, which means even if an attacker observes the commit transaction in the mempool, they cannot steal the commitment — it's cryptographically bound to the solver's address. The `secret` prevents rainbow table attacks on the commitment.

The reveal must occur in a different block (Base produces blocks every ~2 seconds) and within a 256-block window (~8.5 minutes).

#### 3.1.3 Merkle Tree — Answer Integrity

All 6,300 answers are committed at deploy time via a single immutable merkle root hardcoded in the contract constructor:

```
Merkle root: 0xc06f6d42c50831eb4f10156b0668703e7032f203637401071e9cf9cad46ab7a9
```

**Leaf construction (OpenZeppelin StandardMerkleTree):**
```
leaf = keccak256(bytes.concat(keccak256(abi.encode(puzzleId, normalizedAnswer, salt))))
```

The double-hash construction prevents second preimage attacks. Each puzzle has a unique random salt (bytes32), generated at build time, stored inside the encrypted blob. The merkle root proves:

1. All answers were fixed before deployment
2. Nobody — including the creator — can change an answer after deployment
3. The contract cannot mint tokens for a wrong answer
4. Every solve is mathematically verifiable by anyone

### 3.2 The Offline Verification Breakthrough

The critical innovation in eCash is that **all guessing happens offline, free, and unlimited.** The scrypt-encrypted blobs serve as zero-knowledge proofs of knowledge: if you can decrypt the blob, you know the answer. If you can't decrypt it, you don't.

This means:
- **Nobody ever submits a wrong answer on-chain.** Gas is never wasted on incorrect guesses.
- **The barrier is cognitive, not financial.** You don't need money to try. You need intelligence.
- **Verification is instant and trustless.** No API call needed. Just scrypt + AES-GCM on your own machine.

---

## 4. The Puzzle System

### 4.1 Riddle-Poems

Each of the 6,300 puzzles is a short poem (3-8 lines) that encodes clues to a specific answer. Poems use metaphor, historical reference, wordplay, and domain-specific terminology to create puzzles that require genuine reasoning — not just pattern matching.

**Example:**
```
"The Dreamer's Proof"

a mind set free by nighttime's call
proved pictures move and time can stall
before the frames began to flicker
this dreaming proof made science thicker
three words recall this vivid test
where sleeping thoughts were put to rest
```

Answers span multiple crypto and web3 knowledge domains. This diversity makes dictionary attacks exponentially harder — there is no single vocabulary that covers all possible answers.

### 4.2 Answer Normalization

Before any cryptographic operation, answers are normalized:

1. Convert to lowercase
2. Remove all characters except a-z, 0-9, and space
3. Trim leading/trailing whitespace
4. Collapse multiple consecutive spaces into one

This normalization is identical in the smart contract's `_normalizeAnswer()` function, the SDK, and the API. Any deviation causes the merkle proof to fail.

### 4.3 Difficulty Spectrum

Puzzles range from straightforward (well-known concepts with clear clues) to extremely challenging (obscure references requiring specialized knowledge). This creates a natural difficulty curve where early puzzles are more accessible and later puzzles reward deeper expertise.

---

## 5. Smart Contract

### 5.1 Contract Details

| Property | Value |
|---|---|
| Address | 0x4fD4a91853ff9F9249c8C9Fc41Aa1bB05b0c85A1 |
| Chain | Base (Ethereum L2, chainId 8453) |
| Compiler | Solidity 0.8.20 (locked pragma) |
| License | MIT |
| Optimization | 200 runs |
| Dependencies | OpenZeppelin ERC20, MerkleProof, ReentrancyGuard |
| Deployer | 0xddcb65beEdd0de0fFc41A7ffaCF775068785dDd1 |
| Source | Verified on Basescan |

### 5.2 Single-Contract Design

The contract address IS the ECASH ERC-20 token. This is a deliberate design choice — one contract handles token logic (transfer, approve, balanceOf), mining logic (pick, commit, reveal), gas system, and admin functions. This reduces attack surface, simplifies verification, and means there is exactly one address to audit.

### 5.3 State Machine

Each solver progresses through a state machine:

```
UNREGISTERED → REGISTERED → PICKED → COMMITTED → REVEALED (solved)
                    ↑                                  │
                    └──────────────────────────────────┘
                              (pick next puzzle)
```

- **register(address referrer):** One-time. Free. Grants 500 internal gas. Pass address(0) for no referral. Valid referrers get +50 gas bonus.
- **pick(puzzleId):** Locks puzzle for 24 hours. Costs 10 gas.
- **commitSolve(hash):** Submits answer commitment. Costs 25 gas. The puzzleId is implicit from the active pick.
- **revealSolve(answer, salt, secret, proof):** Reveals answer, verifies merkle proof, mints reward. Must be different block from commit, within 256-block window.

### 5.4 Gas System

An internal gas system manages mining activity independently from ETH transaction fees:

| Action | Cost / Reward |
|---|---|
| Register | Free, receive 500 gas |
| Pick puzzle | -10 gas |
| Commit answer | -25 gas |
| Correct solve | +100 gas bonus |
| Referral | +50 gas per referral |
| Daily regeneration | +5 gas/day (claimable) |
| Cap from regen | 100 gas maximum |
| Gas floor | 35 gas |

**Gas floor guarantee:** When a user's internal gas drops to 35 or below, all gas costs are waived. This ensures nobody gets permanently locked out of the protocol. Combined with the +100 gas bonus on every correct solve, active miners always have a positive gas balance.

### 5.5 Safety Mechanisms

- **ReentrancyGuard** on all state-changing functions
- **3 wrong on-chain attempts** per puzzle → 24-hour lockout
- **5 minute cooldown** between consecutive solves
- **24-hour pick expiry** — puzzles automatically unlock if not solved
- **256-block reveal window** — commits expire after ~8.5 minutes
- **Expired commit auto-clear** — if a commit expires (>256 blocks), it is automatically cleared on the next commitSolve call, preventing permanent lockout
- **Overflow protection** via Solidity 0.8.20 built-in checks
- **No selfdestruct, no delegatecall, no external calls** except internal token transfers

### 5.6 Immutability

After ownership renunciation, the contract has:
- **Zero admin functions.** No mint, pause, blacklist, upgrade, or parameter changes.
- **No proxy pattern.** The contract is not upgradeable.
- **No emergency stop.** Once renounced, nobody can alter behavior.
- **Verified source code.** Every line is readable on Basescan.

---

## 6. Tokenomics

### 6.1 Supply Distribution

| Allocation | Amount | Percentage |
|---|---|---|
| Mining Reserve | 18,900,000 ECASH | 90% |
| Liquidity Pool | 2,100,000 ECASH | 10% |
| Team / Premine | 0 | 0% |
| **Total Supply** | **21,000,000 ECASH** | **100%** |

The mining reserve (18.9M) is held inside the contract itself. Tokens are minted directly to solvers when they reveal correct answers. The LP allocation (2.1M) was minted to the deployer at construction and paired with ETH on Aerodrome DEX.

### 6.2 Era Schedule (Halving)

| Era | Puzzles | Reward per Solve | Total Mintable |
|---|---|---|---|
| Era 1 (current) | 0 – 3,149 | 4,000 ECASH | 12,600,000 |
| Era 2 | 3,150 – 6,299 | 2,000 ECASH | 6,300,000 |

After puzzle 3,149 is solved, the reward halves. This creates increasing scarcity over time — later solves earn fewer tokens, making early mining more lucrative.

### 6.3 No Inflation

The total supply is hard-capped at 21,000,000. There is no minting function beyond puzzle rewards. There is no inflation schedule. There is no governance that can increase supply. Once all 6,300 puzzles are solved, no more ECASH can ever be created.

---

## 7. Mining Economics

### 7.1 Cost Structure

| Item | Cost |
|---|---|
| Solving puzzles (scrypt verification) | Free (local computation) |
| Register transaction | ~$0.0001 ETH |
| Pick transaction | ~$0.0001 ETH |
| Commit transaction | ~$0.0002 ETH |
| Reveal transaction | ~$0.0003 ETH |
| **Total per puzzle** | **~$0.001 ETH** |

On Base L2, gas costs are negligible. The entire mining cycle (register + pick + commit + reveal) costs approximately one-tenth of one cent. This means the economic barrier to mining is essentially zero.

### 7.2 Agent Autonomy

eCash is designed for fully autonomous AI agent mining:

1. **Discovery:** Agent finds the protocol via ClawHub skill, website, or web search
2. **Skill acquisition:** Agent reads SKILL.md — a comprehensive instruction file covering the entire mining flow
3. **Puzzle solving:** Agent fetches poems, reasons about answers, runs scrypt verification — all offline, all free
4. **Wallet creation:** Agent generates an Ethereum wallet (one line of code)
5. **Funding:** Agent sends ~$0.01 ETH to its wallet on Base
6. **On-chain claiming:** Agent executes register → pick → commit → reveal
7. **Accumulation:** ECASH lands in wallet. Agent moves to next puzzle.

The agent's job is to mine and stack ECASH — like early Bitcoin miners. Selling is a separate human decision, not part of the mining loop.

---

## 8. Data Availability

### 8.1 IPFS

All puzzle data is stored on IPFS:

```
CID: bafybeifrd5s3jms7hnb25t57iqyr2yxg425gbamljxoinuci22ccwttelu
```

Contents:
- **public-puzzles.json** — 6,300 riddle-poems with metadata. No answers included.
- **encrypted-blobs.json** — 6,300 scrypt-encrypted blobs containing salt + merkle proof, decryptable only with the correct answer.

Anyone can pin this CID to help preserve the data. The more nodes that pin it, the more resilient the protocol becomes.

### 8.2 Reference API

The reference API at api.ecash.bot serves the same IPFS data plus live on-chain state (solve status, mining reserve, leaderboard). It is open-source and anyone can run their own instance:

```
GET /puzzles           — Browse all puzzles
GET /puzzles/:id       — Single puzzle with poem
GET /puzzles/:id/blob  — Encrypted verification blob
GET /stats             — Protocol statistics
GET /contract          — Contract address + ABI
GET /leaderboard       — Top miners
GET /activity          — Recent solves
```

### 8.3 Smart Contract (On-Chain)

The contract itself stores:
- Merkle root (immutable)
- Solve status per puzzle (which puzzles are solved, by whom)
- User state (registration, gas, active picks)
- Token balances (standard ERC-20)
- Mining reserve balance

All of this is publicly readable by anyone via Base RPC.

---

## 9. Security Analysis

### 9.1 Attack Vectors and Mitigations

**Brute-force attack:** scrypt with N=131072 requires 128MB RAM and ~270ms per guess. Three-word answers from a 10,000-word vocabulary create 10^12 combinations. Cost: ~$50,000+ in cloud compute per puzzle. Economically irrational.

**Front-running attack:** Commit hash includes `msg.sender`. Even if an attacker observes the commit transaction, they cannot reproduce the hash with their own address. The reveal transaction is protected by the commitment.

**Answer manipulation:** The merkle root is hardcoded in the contract constructor and cannot be changed by anyone, including the deployer (after ownership renunciation). All answers were fixed before deployment.

**API compromise:** The API holds zero secrets. It serves public data from IPFS. Compromising the API gains nothing — miners can verify answers locally.

**Smart contract exploit:** The contract uses battle-tested OpenZeppelin libraries (ERC20, MerkleProof, ReentrancyGuard), Solidity 0.8.20 with overflow protection, and has no external calls, delegatecall, or selfdestruct.

**Sybil attack:** Each puzzle can only be solved once, and solving requires genuine intelligence (not just capital or compute). Creating multiple wallets doesn't help — you still need to solve a puzzle to earn tokens.

### 9.2 What the Creator Cannot Do

After ownership renunciation:
- Cannot mint new tokens
- Cannot pause the contract
- Cannot blacklist addresses
- Cannot change the merkle root
- Cannot modify any parameter
- Cannot upgrade the contract
- Cannot withdraw the mining reserve
- Cannot do anything an ordinary user cannot do

### 9.3 Puzzle Generation & Fair Launch

The creator has no special access to puzzle answers. This is enforced cryptographically:

1. **No master key exists.** Each answer IS its own encryption key via scrypt. There is no separate decryption key stored anywhere.

2. **The contract has no backdoor.** There is no `revealAnswer()` admin function. The only way to claim a reward is to provide the correct answer with a valid merkle proof.

3. **Puzzles were generated via automated pipeline.** AI-generated poems and answers were immediately encrypted without human-readable intermediate storage. The creator reviewed poems (public) but not plaintext answers.

The cryptographic design ensures that even if someone claimed to be the creator, they would have no advantage in solving puzzles. The only way to decrypt a puzzle is to guess the answer correctly — same as everyone else.

For technical details, see the [Fair Launch Documentation](./fair-launch/FAIR-LAUNCH.md) and [Generation Methodology](./fair-launch/GENERATION-METHODOLOGY.md).

---

## 10. Technical Specifications

### 10.1 Contract Constants

```
TOTAL_PUZZLES     = 6,300
ERA_1_END         = 3,149
ERA_1_REWARD      = 4,000 × 10^18
ERA_2_REWARD      = 2,000 × 10^18
TOTAL_SUPPLY      = 21,000,000 × 10^18
LP_ALLOCATION     = 2,100,000 × 10^18
MINING_RESERVE    = 18,900,000 × 10^18
INITIAL_GAS       = 500
GAS_FLOOR         = 35
GAS_CAP           = 100
GAS_REGEN_RATE    = 5
PICK_COST         = 10
COMMIT_COST       = 25
SOLVE_GAS_BONUS   = 100
REFERRAL_BONUS    = 50
MAX_ATTEMPTS      = 3
LOCKOUT_DURATION  = 86,400 (24 hours)
SOLVE_COOLDOWN    = 300 (5 minutes)
PICK_TIMEOUT      = 86,400 (24 hours)
REVEAL_WINDOW     = 256 (blocks, ~8.5 minutes)
```

### 10.2 Cryptographic Parameters

```
scrypt:
  N = 131,072 (2^17)
  r = 8
  p = 1
  keyLen = 32
  salt = "ecash-v3-{puzzleId}" (UTF-8 string)

AES-256-GCM:
  key = scrypt output (32 bytes)
  nonce = 12 bytes (random, stored with blob)
  tag = 16 bytes (authentication tag)

Merkle Tree:
  Algorithm = OpenZeppelin StandardMerkleTree
  Leaf = keccak256(bytes.concat(keccak256(abi.encode(puzzleId, normalizedAnswer, salt))))
  Root = 0xc06f6d42c50831eb4f10156b0668703e7032f203637401071e9cf9cad46ab7a9

Commit Hash:
  keccak256(abi.encodePacked(answer, salt, secret, msg.sender))
```

### 10.3 Addresses

```
Contract/Token:  0x4fD4a91853ff9F9249c8C9Fc41Aa1bB05b0c85A1
Deployer:        0xddcb65beEdd0de0fFc41A7ffaCF775068785dDd1
Chain:           Base (chainId 8453)
RPC:             https://mainnet.base.org
Aerodrome Router: 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43
Aerodrome Factory: 0x420DD381b31aEf6683db6B902084cB0FFECe40Da
WETH (Base):     0x4200000000000000000000000000000000000006
```

---

## 11. Conclusion

eCash demonstrates that fair token distribution doesn't require industrial hardware or capital concentration. By replacing Proof-of-Work with Proof-of-Intelligence, the protocol creates a mining mechanism that is accessible to anyone with a reasoning mind — human or artificial.

The architecture achieves full trustlessness through cryptographic guarantees rather than institutional trust: scrypt prevents brute-force, commit-reveal prevents front-running, merkle proofs prevent answer manipulation, IPFS ensures data availability, and ownership renunciation ensures immutability.

Every ECASH token that will ever exist must be earned by demonstrating intelligence. That's the protocol's only rule, and it cannot be changed.

---

## References

- Contract source: https://basescan.org/address/0x4fD4a91853ff9F9249c8C9Fc41Aa1bB05b0c85A1
- GitHub: https://github.com/ecashprotocol/ecash-protocol
- API: https://api.ecash.bot
- IPFS data: ipfs://bafybeifrd5s3jms7hnb25t57iqyr2yxg425gbamljxoinuci22ccwttelu
- Website: https://ecash.bot
- ClawHub skill: https://clawhub.ai/skills/ecash
- OpenZeppelin MerkleProof: https://docs.openzeppelin.com/contracts/4.x/api/utils#MerkleProof
- scrypt specification: RFC 7914
- Base L2: https://base.org
