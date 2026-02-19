#!/usr/bin/env node
/**
 * eCash Puzzle Generation Pipeline
 *
 * METHODOLOGY DEMONSTRATION
 *
 * This script generates puzzles using AI and immediately encrypts answers
 * without human-readable intermediate storage. The operator sees only:
 * - The riddle poems (public)
 * - Encrypted blobs (opaque)
 * - Merkle root (commitment)
 *
 * The plaintext answers exist only in memory during generation and are
 * never written to disk unencrypted.
 *
 * Usage: ANTHROPIC_API_KEY=... node generate-puzzles.js --count 10 --start-id 0
 */

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

// Encryption parameters (must match contract)
const SCRYPT_N = 131072;
const SCRYPT_R = 8;
const SCRYPT_P = 1;
const SCRYPT_KEYLEN = 32;

/**
 * Normalize answer to match contract's _normalizeAnswer()
 */
function normalize(answer) {
  return answer
    .toLowerCase()
    .replace(/[^a-z0-9 ]/g, '')
    .trim()
    .replace(/\s+/g, ' ');
}

/**
 * Encrypt answer data using scrypt-derived key
 * Answer is used as password - no separate key storage
 */
function encryptWithAnswer(puzzleId, normalizedAnswer, salt, proof) {
  const scryptSalt = `ecash-v3-${puzzleId}`;

  // Derive key from answer - answer IS the key
  const key = crypto.scryptSync(
    Buffer.from(normalizedAnswer, 'utf-8'),
    Buffer.from(scryptSalt, 'utf-8'),
    SCRYPT_KEYLEN,
    { N: SCRYPT_N, r: SCRYPT_R, p: SCRYPT_P, maxmem: 256 * 1024 * 1024 }
  );

  // Encrypt the salt + proof payload
  const nonce = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, nonce);

  const payload = JSON.stringify({ salt, proof });
  const encrypted = Buffer.concat([cipher.update(payload, 'utf-8'), cipher.final()]);
  const tag = cipher.getAuthTag();

  return {
    puzzleId,
    blob: encrypted.toString('hex'),
    nonce: nonce.toString('hex'),
    tag: tag.toString('hex')
  };
}

/**
 * Generate merkle leaf for a puzzle
 */
function generateMerkleLeaf(puzzleId, normalizedAnswer, salt) {
  const { ethers } = require('ethers');
  const inner = ethers.keccak256(
    ethers.AbiCoder.defaultAbiCoder().encode(
      ['uint256', 'string', 'bytes32'],
      [puzzleId, normalizedAnswer, salt]
    )
  );
  return ethers.keccak256(ethers.concat([inner]));
}

/**
 * Build merkle tree and return root + proofs
 */
function buildMerkleTree(leaves) {
  const { ethers } = require('ethers');

  if (leaves.length === 0) return { root: ethers.ZeroHash, proofs: [] };

  // Pad to power of 2
  const targetSize = Math.pow(2, Math.ceil(Math.log2(leaves.length)));
  const paddedLeaves = [...leaves];
  while (paddedLeaves.length < targetSize) {
    paddedLeaves.push(ethers.ZeroHash);
  }

  // Build tree layers
  const layers = [paddedLeaves];
  while (layers[layers.length - 1].length > 1) {
    const currentLayer = layers[layers.length - 1];
    const nextLayer = [];
    for (let i = 0; i < currentLayer.length; i += 2) {
      const left = currentLayer[i];
      const right = currentLayer[i + 1];
      const [sortedLeft, sortedRight] = left < right ? [left, right] : [right, left];
      nextLayer.push(ethers.keccak256(ethers.concat([sortedLeft, sortedRight])));
    }
    layers.push(nextLayer);
  }

  // Extract proofs
  const proofs = leaves.map((_, index) => {
    const proof = [];
    let idx = index;
    for (let i = 0; i < layers.length - 1; i++) {
      const siblingIdx = idx % 2 === 0 ? idx + 1 : idx - 1;
      if (siblingIdx < layers[i].length) {
        proof.push(layers[i][siblingIdx]);
      }
      idx = Math.floor(idx / 2);
    }
    return proof;
  });

  return {
    root: layers[layers.length - 1][0],
    proofs
  };
}

/**
 * Call Claude API to generate a puzzle
 * Returns { poem, answer } where answer is 3+ words
 */
async function generatePuzzleFromAI(puzzleId, apiKey) {
  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01'
    },
    body: JSON.stringify({
      model: 'claude-sonnet-4-20250514',
      max_tokens: 500,
      messages: [{
        role: 'user',
        content: `Generate a cryptographic riddle puzzle for a blockchain mining game.

Requirements:
1. Write a 4-line poem that contains clues to the answer
2. The answer MUST be exactly 3-5 words (e.g., "the rosetta stone", "proof of work")
3. Clues should be embedded in metaphors, wordplay, or references
4. Topics: crypto, blockchain, computer science, mathematics, famous algorithms, protocols

Respond in this exact JSON format only, no other text:
{"poem": "line1\\nline2\\nline3\\nline4", "answer": "three to five words"}

Puzzle ID: ${puzzleId}`
      }]
    })
  });

  const data = await response.json();
  const content = data.content[0].text;

  // Parse JSON response
  const parsed = JSON.parse(content);

  // Validate answer is 3+ words
  const wordCount = parsed.answer.trim().split(/\s+/).length;
  if (wordCount < 3) {
    throw new Error(`Answer "${parsed.answer}" has only ${wordCount} words, need 3+`);
  }

  return parsed;
}

/**
 * Main generation pipeline
 *
 * CRITICAL: Answers exist only in memory and are immediately encrypted.
 * No plaintext answer file is ever created.
 */
async function main() {
  const args = process.argv.slice(2);
  const countIdx = args.indexOf('--count');
  const startIdx = args.indexOf('--start-id');

  const count = countIdx !== -1 ? parseInt(args[countIdx + 1]) : 10;
  const startId = startIdx !== -1 ? parseInt(args[startIdx + 1]) : 0;

  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    console.error('Error: ANTHROPIC_API_KEY environment variable required');
    process.exit(1);
  }

  console.log(`Generating ${count} puzzles starting at ID ${startId}...`);
  console.log('Answers will be encrypted immediately - no plaintext storage.\n');

  const puzzles = [];      // Public: { id, poem } - no answers
  const blobs = [];        // Public: encrypted blobs
  const leaves = [];       // Internal: for merkle tree

  for (let i = 0; i < count; i++) {
    const puzzleId = startId + i;
    process.stdout.write(`Puzzle ${puzzleId}: generating... `);

    try {
      // Generate puzzle from AI
      const { poem, answer } = await generatePuzzleFromAI(puzzleId, apiKey);

      // Normalize answer (in memory only)
      const normalizedAnswer = normalize(answer);

      // Generate random salt for merkle tree
      const salt = '0x' + crypto.randomBytes(32).toString('hex');

      // Generate merkle leaf
      const leaf = generateMerkleLeaf(puzzleId, normalizedAnswer, salt);
      leaves.push(leaf);

      // Build proof placeholder (will be filled after tree is complete)
      // For now, store the data needed
      puzzles.push({
        id: puzzleId,
        poem: poem,
        // NOTE: answer is NOT stored here
      });

      // Store temp data for encryption (answer in memory only)
      blobs.push({
        puzzleId,
        normalizedAnswer,  // Temporary - will be cleared
        salt
      });

      console.log(`done (${normalizedAnswer.split(' ').length} words)`);

      // Rate limit
      await new Promise(r => setTimeout(r, 1000));

    } catch (error) {
      console.log(`failed: ${error.message}`);
      // Retry logic could go here
    }
  }

  console.log('\nBuilding merkle tree...');
  const { root, proofs } = buildMerkleTree(leaves);
  console.log(`Merkle root: ${root}`);

  console.log('\nEncrypting answers...');
  const encryptedBlobs = [];

  for (let i = 0; i < blobs.length; i++) {
    const { puzzleId, normalizedAnswer, salt } = blobs[i];
    const proof = proofs[i];

    // Encrypt - after this, normalizedAnswer is no longer needed
    const encrypted = encryptWithAnswer(puzzleId, normalizedAnswer, salt, proof);
    encryptedBlobs.push(encrypted);

    // Clear answer from memory (JS doesn't guarantee this, but conceptually)
    blobs[i].normalizedAnswer = null;
  }

  // Write outputs - NO ANSWERS in any file
  const outputDir = path.join(__dirname, '../generated');
  if (!fs.existsSync(outputDir)) fs.mkdirSync(outputDir, { recursive: true });

  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');

  // Public puzzles (poems only, no answers)
  fs.writeFileSync(
    path.join(outputDir, `puzzles-${timestamp}.json`),
    JSON.stringify(puzzles, null, 2)
  );

  // Encrypted blobs
  fs.writeFileSync(
    path.join(outputDir, `blobs-${timestamp}.json`),
    JSON.stringify(encryptedBlobs, null, 2)
  );

  // Merkle root
  fs.writeFileSync(
    path.join(outputDir, `merkle-${timestamp}.json`),
    JSON.stringify({ root, leafCount: leaves.length }, null, 2)
  );

  console.log(`\nGeneration complete!`);
  console.log(`Output directory: ${outputDir}`);
  console.log(`\nFiles created:`);
  console.log(`  - puzzles-${timestamp}.json (poems only, NO answers)`);
  console.log(`  - blobs-${timestamp}.json (encrypted, answers unrecoverable without solving)`);
  console.log(`  - merkle-${timestamp}.json (root commitment)`);
  console.log(`\nThe operator has NOT seen any plaintext answers.`);
  console.log(`Answers existed only in memory during generation and were immediately encrypted.`);
}

main().catch(console.error);
