# eCash Puzzle Generation Methodology

## Overview

eCash puzzles are generated using an automated pipeline that ensures **no human ever sees the plaintext answers**. This document explains how this is achieved and how it can be verified.

## The Problem

In a puzzle-reward system, if the creator knows the answers, they could:
1. Solve puzzles themselves and claim rewards
2. Share answers with accomplices
3. Front-run legitimate solvers

## The Solution: Answer-as-Key Encryption

eCash uses a cryptographic design where **the answer IS the encryption key**:

```
answer → normalize → scrypt → AES-256-GCM key
```

There is no separate "master key" or "decryption key" stored anywhere. The only way to decrypt a puzzle's payload is to know the answer.

## Generation Pipeline

```
┌─────────────────┐
│   Claude AI     │
│  (generates     │
│ poem + answer)  │
└────────┬────────┘
         │ JSON response (in memory)
         ▼
┌─────────────────┐
│   Normalize     │
│   (in memory)   │
└────────┬────────┘
         │
    ┌────┴────┐
    ▼         ▼
┌───────┐ ┌──────────┐
│ Poem  │ │  Answer  │
│(save) │ │(encrypt) │
└───────┘ └────┬─────┘
               │ scrypt + AES-256-GCM
               ▼
         ┌──────────┐
         │Encrypted │
         │  Blob    │
         │ (save)   │
         └──────────┘
```

**Key points:**
- Answers exist only in memory during the generation script
- Answers are immediately encrypted using themselves as the key
- No plaintext answer file is ever written to disk
- The operator sees only: poems (public) + encrypted blobs (opaque)

## What the Operator Sees

| Data | Operator Access | Public |
|------|-----------------|--------|
| Poems | Yes (reviews for quality) | Yes |
| Encrypted blobs | Yes (opaque hex data) | Yes |
| Merkle root | Yes | Yes (on-chain) |
| **Plaintext answers** | **No** | No |

## Verification

### 1. Code Review

The generation script (`generate-puzzles.js`) can be audited:
- AI response is parsed in memory
- Answer is normalized in memory
- Answer is immediately passed to `encryptWithAnswer()`
- No `fs.writeFileSync()` call includes plaintext answers
- Output files contain only: `{ id, poem }` and encrypted blobs

### 2. Cryptographic Verification

Each encrypted blob can only be decrypted by:
```javascript
scryptSync(normalizedAnswer, `ecash-v3-${puzzleId}`, ...)
```

There is no alternative decryption path. No master key exists.

### 3. Contract Verification

The smart contract has:
- No `revealAnswer()` admin function
- No decryption capability
- Only merkle proof verification

The contract cannot reveal answers — it can only verify them.

## What This Means

1. **Creator cannot solve puzzles** without guessing like everyone else
2. **No insider trading** is possible
3. **Rewards are earned fairly** by whoever solves first

## Reproducing the Pipeline

To generate new puzzles with the same methodology:

```bash
export ANTHROPIC_API_KEY="your-key"
node scripts/generate-puzzles.js --count 10 --start-id 0
```

Output:
- `generated/puzzles-{timestamp}.json` — poems only
- `generated/blobs-{timestamp}.json` — encrypted blobs
- `generated/merkle-{timestamp}.json` — merkle root

## FAQ

**Q: Could the operator have saved answers before encrypting?**
A: The script doesn't write answers anywhere. You can audit every line.

**Q: Could there be a backdoor in the encryption?**
A: Standard scrypt + AES-256-GCM. No custom crypto. Verify with any implementation.

**Q: How do we know this script was actually used?**
A: The cryptographic design (answer-as-key) makes it irrelevant. Even if a different script was used, there's no master key. The only way to decrypt is to know the answer.

**Q: Can the creator brute-force their own puzzles?**
A: scrypt with N=131072 takes ~300ms per attempt. Brute-forcing 3+ word answers from a large vocabulary is computationally infeasible.

## Conclusion

The eCash puzzle system is designed so that **knowing the encryption scheme gives no advantage**. The security comes from the cryptographic design, not from keeping the process secret.

The creator has no special access to answers. They must solve puzzles the same way as everyone else.
