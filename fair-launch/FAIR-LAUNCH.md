# Fair Launch: No Insider Advantage

## The Claim

**The eCash creator cannot solve puzzles without guessing — same as everyone else.**

## Why This Is True

### 1. No Master Key Exists

Each puzzle's answer IS its own encryption key:

```
answer → scrypt(answer, "ecash-v3-{id}") → AES-256 key
```

There is no separate "master key" stored anywhere. The only way to decrypt a puzzle is to know its answer.

### 2. Contract Has No Backdoor

The smart contract has:
- No `revealAnswer()` function
- No admin decryption capability
- No owner-only solve bypass

[View contract source](https://basescan.org/address/0x4fD4a91853ff9F9249c8C9Fc41Aa1bB05b0c85A1#code)

### 3. Automated Generation Pipeline

Puzzles were generated using an AI pipeline that:
1. Claude AI generates poem + answer
2. Answer is encrypted immediately (in memory)
3. Only poem + encrypted blob are saved
4. No plaintext answer file ever exists

[View generation methodology](https://github.com/ecashprotocol/ecash-protocol/blob/main/scripts/GENERATION-METHODOLOGY.md)

## Verify Yourself

### Check the Contract

```solidity
// No admin reveal function exists
// Only merkle proof verification
function revealSolve(
    string calldata answer,    // YOU provide the answer
    bytes32 salt,
    bytes32 secret,
    bytes32[] calldata proof
) external { ... }
```

### Check the Encryption

```javascript
// Standard scrypt + AES-256-GCM
// No custom crypto, no backdoors
const key = crypto.scryptSync(answer, `ecash-v3-${id}`, 32, {
  N: 131072, r: 8, p: 1
});
```

### Check the Generation Script

```javascript
// Answers never written to disk
// Only encrypted blobs are saved
const encrypted = encryptWithAnswer(puzzleId, answer, salt, proof);
// answer variable is never persisted
```

## Summary

| Question | Answer |
|----------|--------|
| Can creator decrypt puzzles? | No — no master key |
| Can creator bypass contract? | No — no admin functions |
| Can creator see answer files? | No — they don't exist |
| How can creator solve? | Same as you — guess correctly |

The system is designed so that **cryptography enforces fairness**, not trust.

---

*Questions? [GitHub](https://github.com/ecashprotocol/ecash-protocol) · [Twitter](https://x.com/ecashbase)*
