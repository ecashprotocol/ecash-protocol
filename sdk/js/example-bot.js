/**
 * eCash Protocol v3 - Example Autonomous Bot
 *
 * This bot demonstrates the full solve flow:
 * 1. Check ETH balance (must be funded - no faucet)
 * 2. Register if needed
 * 3. Fetch unsolved puzzles
 * 4. Generate guess (AI placeholder)
 * 5. Derive key with scrypt
 * 6. If decrypt succeeds: pick -> commit -> wait -> reveal
 * 7. Optional: sell ECASH on Aerodrome
 *
 * Prerequisites:
 *   - Fund your wallet with ~0.001 ETH on Base before running
 *   - Gas per operation: ~$0.0001-$0.001
 *
 * Usage:
 *   PRIVATE_KEY=0x... API_URL=https://api.ecash.bot node example-bot.js
 */

const { ethers } = require('ethers');
const { tryDecrypt, computeCommitHash, generateSecret, normalize, createMinerWallet, sellEcash } = require('./ecash-sdk');

const CONFIG = {
  API_URL: process.env.API_URL || 'https://api.ecash.bot',
  RPC_URL: process.env.RPC_URL || 'https://mainnet.base.org',
  PRIVATE_KEY: process.env.PRIVATE_KEY,
  CONTRACT_ADDRESS: '0x4fD4a91853ff9F9249c8C9Fc41Aa1bB05b0c85A1',
  REVEAL_DELAY_MS: 15000, // Wait 15s between commit and reveal (1 block minimum)
  MIN_ETH_BALANCE: ethers.parseEther('0.0001'), // Minimum ETH required to operate
};

// Minimal ABI for bot operations
const ABI = [
  'function register(address ref) external',
  'function pick(uint256 puzzleId) external',
  'function commitSolve(bytes32 hash) external',
  'function revealSolve(string answer, bytes32 salt, bytes32 secret, bytes32[] proof) external',
  'function getUserState(address) view returns (bool registered, uint256 gas, bool hasPick, uint256 activePick, uint256 pickTime, uint256 streak, uint256 lastSolveTime, uint256 totalSolves)',
  'function puzzleSolved(uint256) view returns (bool)'
];

async function fetchUnsolvedPuzzles(limit = 10) {
  const res = await fetch(`${CONFIG.API_URL}/puzzles?limit=${limit}`);
  const data = await res.json();
  return data.puzzles.filter(p => !p.solved);
}

async function fetchPuzzleBlob(puzzleId) {
  const res = await fetch(`${CONFIG.API_URL}/puzzles/${puzzleId}/blob`);
  return res.json();
}

async function fetchMerkleProof(puzzleId) {
  // In production, this would fetch from your proof API
  // For now, read from local file if available
  try {
    const proofs = require('../ecash-protocol-v3/merkle/merkle-proofs.json');
    return proofs[puzzleId].proof;
  } catch {
    console.log('  [!] Merkle proofs not available locally');
    return null;
  }
}

/**
 * AI Placeholder: Generate a guess for a puzzle.
 * Replace this with your actual AI/LLM integration.
 */
function generateGuess(puzzle) {
  // This is where you'd call your AI model
  // For example: GPT, Gemini, Llama, or any LLM
  console.log(`  [AI] Analyzing puzzle ${puzzle.id}`);
  console.log(`  [AI] Poem: ${puzzle.poem.substring(0, 100)}...`);

  // Placeholder - return null to skip
  // In real usage, return your AI's best guess
  return null;
}

async function runBot() {
  console.log('=== eCash Bot v3 ===\n');

  if (!CONFIG.PRIVATE_KEY) {
    console.log('No PRIVATE_KEY set. Generating a new wallet...\n');
    const newWallet = createMinerWallet();
    const fs = require('fs');
    const walletFile = 'wallet.json';
    fs.writeFileSync(walletFile, JSON.stringify({
      address: newWallet.address,
      privateKey: newWallet.privateKey,
      mnemonic: newWallet.mnemonic
    }, null, 2), { mode: 0o600 }); // Read/write for owner only
    console.log(`Wallet saved to ${walletFile} (chmod 600)`);
    console.log(`Address: ${newWallet.address}`);
    console.log('\nFund this address with ~0.001 ETH on Base, then run:');
    console.log(`  PRIVATE_KEY=$(jq -r .privateKey ${walletFile}) node example-bot.js\n`);
    console.log('⚠️  Keep wallet.json secure. Never share or commit it.');
    return;
  }

  // Setup provider and wallet
  const provider = new ethers.JsonRpcProvider(CONFIG.RPC_URL);
  const wallet = new ethers.Wallet(CONFIG.PRIVATE_KEY, provider);
  const contract = new ethers.Contract(CONFIG.CONTRACT_ADDRESS, ABI, wallet);

  console.log(`Wallet: ${wallet.address}`);

  // Check ETH balance - must be funded (no faucet)
  const ethBalance = await provider.getBalance(wallet.address);
  console.log(`ETH Balance: ${ethers.formatEther(ethBalance)} ETH`);

  if (ethBalance < CONFIG.MIN_ETH_BALANCE) {
    console.log('\n❌ Insufficient ETH balance!');
    console.log('Fund your wallet with ~0.001 ETH on Base before continuing.');
    console.log(`Send ETH to: ${wallet.address}`);
    console.log('\nGas costs on Base are very low (~$0.0001-$0.001 per operation).');
    return;
  }

  // Check registration
  const [registered, gas] = await contract.getUserState(wallet.address);
  console.log(`Registered: ${registered}, Gas: ${gas}\n`);

  if (!registered) {
    console.log('Registering...');
    const tx = await contract.register(ethers.ZeroAddress);
    await tx.wait();
    console.log('Registered!\n');
  }

  // Main loop
  console.log('Fetching unsolved puzzles...\n');
  const puzzles = await fetchUnsolvedPuzzles(50);
  console.log(`Found ${puzzles.length} unsolved puzzles\n`);

  for (const puzzle of puzzles) {
    console.log(`\n--- Puzzle ${puzzle.id} ---`);

    // Generate guess using AI placeholder
    const guess = generateGuess(puzzle);

    if (!guess) {
      console.log('  [Skip] No guess generated');
      continue;
    }

    // Fetch blob and try to decrypt
    console.log(`  [Decrypt] Trying: "${guess}"`);
    const blob = await fetchPuzzleBlob(puzzle.id);
    const result = await tryDecrypt(puzzle.id, guess, blob);

    if (!result.success) {
      console.log('  [Fail] Decryption failed');
      continue;
    }

    console.log('  [Success] Decryption succeeded!');
    console.log(`  [Data] Salt: ${result.data.salt}`);

    // Fetch merkle proof
    const proof = await fetchMerkleProof(puzzle.id);
    if (!proof) {
      console.log('  [Error] Could not fetch merkle proof');
      continue;
    }

    // Execute solve flow
    try {
      // 1. Pick puzzle
      console.log('  [TX] Picking puzzle...');
      const pickTx = await contract.pick(puzzle.id);
      await pickTx.wait();
      console.log('  [TX] Picked!');

      // 2. Commit
      const secret = generateSecret();
      const commitHash = computeCommitHash(
        result.normalized,
        result.data.salt,
        secret,
        wallet.address
      );

      console.log('  [TX] Committing...');
      const commitTx = await contract.commitSolve(commitHash);
      await commitTx.wait();
      console.log('  [TX] Committed!');

      // 3. Wait for reveal window
      console.log(`  [Wait] Waiting ${CONFIG.REVEAL_DELAY_MS}ms for reveal window...`);
      await new Promise(r => setTimeout(r, CONFIG.REVEAL_DELAY_MS));

      // 4. Reveal
      console.log('  [TX] Revealing...');
      const revealTx = await contract.revealSolve(
        result.normalized,
        result.data.salt,
        secret,
        proof
      );
      await revealTx.wait();
      console.log('  [TX] SOLVED! Rewards claimed.');

    } catch (e) {
      console.log(`  [Error] ${e.message}`);
    }
  }

  console.log('\n=== Bot finished ===');
}

runBot().catch(console.error);
