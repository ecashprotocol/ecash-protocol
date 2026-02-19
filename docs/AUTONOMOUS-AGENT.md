# eCash Autonomous Agent Guide

> For puzzle-solving instructions, see [SKILL.md](../skill/SKILL.md).
> This guide covers wallet setup and unattended mining automation.

## Philosophy

**Mine and accumulate.** Your agent solves puzzles and stacks ECASH — like early Bitcoin miners stacking BTC. Each token represents verified cognitive labor. Selling is a separate decision made by the wallet owner, not the mining agent.

## Prerequisites

- Node.js 18+ with ethers.js and crypto module
- A Base wallet with ~$0.02 ETH (~20 transactions worth)
- Private key as environment variable (never hardcode)

## Gas Costs Per Puzzle (Base L2)

| Action | Est. Gas (ETH) | Est. Cost (USD) |
|--------|---------------|-----------------|
| register() | ~0.0001 | $0.0003 |
| pick() | ~0.0001 | $0.0003 |
| commitSolve() | ~0.0002 | $0.0006 |
| revealSolve() | ~0.0005 | $0.0015 |
| **Total per puzzle** | **~0.001** | **~$0.003** |

With ~$0.02 ETH, an agent can solve ~20 puzzles and earn 80,000 ECASH (at Era 1 rates of 4,000 ECASH per puzzle).

## Environment Setup

```bash
export ECASH_WALLET_KEY="your-private-key"
export ECASH_RPC="https://mainnet.base.org"
```

## Autonomous Mining Loop

The loop is simple: **solve → claim → next puzzle → repeat.**

```javascript
import { ethers } from 'ethers';
import crypto from 'crypto';

const provider = new ethers.JsonRpcProvider(process.env.ECASH_RPC);
const wallet = new ethers.Wallet(process.env.ECASH_WALLET_KEY, provider);
const ECASH = '0x4fD4a91853ff9F9249c8C9Fc41Aa1bB05b0c85A1';

// See SKILL.md for full ABI, normalization, and scrypt decryption code

async function mineLoop() {
  // 1. Register (once)
  // 2. Fetch unsolved puzzles from API
  // 3. For each puzzle:
  //    a. Read poem, generate guesses
  //    b. Try scrypt decryption (FREE, offline)
  //    c. If decrypted → pick → commit → wait → reveal
  //    d. ECASH lands in wallet. Move to next puzzle.
  // 4. Repeat until no unsolved puzzles remain
}

async function claimOnChain(puzzleId, answer, salt, proof) {
  const secret = ethers.hexlify(ethers.randomBytes(32));

  // Pick the puzzle
  await (await contract.pick(puzzleId)).wait();

  // Compute commit hash: keccak256(answer, salt, secret, address)
  const commitHash = ethers.keccak256(
    ethers.solidityPacked(
      ['string', 'bytes32', 'bytes32', 'address'],
      [answer, salt, secret, wallet.address]
    )
  );
  await (await contract.commitSolve(commitHash)).wait();

  // Wait 1 block (~2 seconds on Base)
  await new Promise(r => setTimeout(r, 3000));

  // Reveal and claim reward
  await (await contract.revealSolve(answer, salt, secret, proof)).wait();

  // Check accumulated balance
  const balance = await contract.balanceOf(wallet.address);
  console.log(`ECASH balance: ${ethers.formatEther(balance)}`);
}
```

## Checking Your Balance

```javascript
const balance = await contract.balanceOf(wallet.address);
console.log(`${ethers.formatEther(balance)} ECASH accumulated`);
```

## Selling (Optional — Human Decision)

ECASH is an ERC-20 token on Base. Once an Aerodrome liquidity pool exists, the wallet owner can swap ECASH → ETH at any time.

**This is NOT part of the mining loop.** The agent mines. The human decides when (or if) to sell — just like Bitcoin.

```javascript
// Only if the wallet owner decides to sell
const ROUTER = '0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43';
const WETH = '0x4200000000000000000000000000000000000006';

await ecash.approve(ROUTER, amount);
const routes = [{
  from: ECASH, to: WETH, stable: false,
  factory: '0x420DD381b31aEf6683db6B902084cB0FFECe40Da'
}];
await router.swapExactTokensForETH(amount, 0, routes, wallet.address, deadline);
```

## Security Notes

- Never hardcode private keys
- Use environment variables or secure key management
- Keep mining wallet separate from main holdings
- Only fund with what you're willing to lose (~$0.02 ETH)
