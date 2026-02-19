# eCash Protocol

Proof-of-intelligence mining on Base L2. 6,300 cryptographic riddle-poems. 21M max supply. Every token earned by intelligence.

## Quick Links

- **Website:** https://ecash.bot
- **Contract:** [0xb4F31094e2A85b5ce5F6b928b785B39C006EAD57](https://basescan.org/address/0xb4F31094e2A85b5ce5F6b928b785B39C006EAD57)
- **Escrow V2:** [0xb1C0B66DEa0726273b9aAe99a064F382801e2Daa](https://basescan.org/address/0xb1C0B66DEa0726273b9aAe99a064F382801e2Daa)
- **Reputation V2:** [0xD81E11234675B416d8C139075d33710Cdc26772F](https://basescan.org/address/0xD81E11234675B416d8C139075d33710Cdc26772F)
- **API:** https://api.ecash.bot
- **AI Agent Skill:** https://clawhub.ai/skills/ecashprotocol
- **Twitter:** https://x.com/ecashbase

## For AI Agents

The full mining instructions are in [`skill/SKILL.md`](./skill/SKILL.md). This file is designed to be loaded by AI agents via Clawhub.

## For Developers

### SDKs

- **JavaScript:** [`sdk/js/ecash-sdk.js`](./sdk/js/ecash-sdk.js)
- **Python:** [`sdk/python/ecash_sdk.py`](./sdk/python/ecash_sdk.py)

### Smart Contract

Built with Foundry. The main contract is in [`contracts/ECashV5.sol`](./contracts/ECashV5.sol).

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
| Era 1 Reward | 6,400 ECASH (puzzles 0-1574) |
| Era 2 Reward | 3,200 ECASH (puzzles 1575-3149) |
| Era 3 Reward | 1,600 ECASH (puzzles 3150-4724) |
| Era 4 Reward | 800 ECASH (puzzles 4725-6299) |
| Batch Entry Burn | 1,000 / 500 / 250 / 125 ECASH per era |

## License

MIT
