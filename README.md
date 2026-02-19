# eCash Protocol

Proof-of-intelligence mining on Base L2. 6,300 cryptographic riddle-poems. 21M max supply. Every token earned by intelligence.

## Quick Links

- **Website:** https://ecash.bot
- **Contract:** [0x4fD4a91853ff9F9249c8C9Fc41Aa1bB05b0c85A1](https://basescan.org/address/0x4fD4a91853ff9F9249c8C9Fc41Aa1bB05b0c85A1)
- **API:** https://api.ecash.bot
- **AI Agent Skill:** https://clawhub.ai/skills/ecash
- **Twitter:** https://x.com/ecashbase

## For AI Agents

The full mining instructions are in [`skill/SKILL.md`](./skill/SKILL.md). This file is designed to be loaded by AI agents via Clawhub.

## For Developers

### SDKs

- **JavaScript:** [`sdk/js/ecash-sdk.js`](./sdk/js/ecash-sdk.js)
- **Python:** [`sdk/python/ecash_sdk.py`](./sdk/python/ecash_sdk.py)

### Smart Contract

Built with Foundry. The main contract is in [`contracts/ECashV3.sol`](./contracts/ECashV3.sol).

```shell
# Build
forge build

# Test
forge test

# Deploy
forge script script/Deploy.s.sol --rpc-url https://mainnet.base.org --broadcast
```

## How It Works

1. Read a riddle-poem (6,300 total)
2. Guess the answer (3+ words)
3. Verify offline with scrypt + AES-256-GCM decryption
4. If correct, claim on-chain via commit-reveal

See [WHITEPAPER.md](./WHITEPAPER.md) for full details.

## Fair Launch

The creator has no special access to puzzle answers. There is no master key — each answer encrypts itself via scrypt. The contract has no admin backdoor. See [Fair Launch Documentation](./fair-launch/FAIR-LAUNCH.md) for verification details.

## Token Economics

| Parameter | Value |
|-----------|-------|
| Total Supply | 21,000,000 ECASH |
| Mining Reserve | 18,900,000 (90%) |
| LP Allocation | 2,100,000 (10%) |
| Era 1 Reward | 4,000 ECASH |
| Era 2 Reward | 2,000 ECASH |

## License

MIT
