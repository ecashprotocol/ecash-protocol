/**
 * eCash Protocol v3 SDK
 *
 * Utility functions for solving puzzles on the eCash protocol.
 *
 * Installation:
 *   npm install scrypt-js ethers
 *
 * Usage:
 *   const { normalize, tryDecrypt, computeCommitHash } = require('./ecash-sdk');
 */

const { scrypt } = require('scrypt-js');
const { ethers } = require('ethers');
const crypto = require('crypto');

// Contract addresses
const ECASH_ADDRESS = '0x4fD4a91853ff9F9249c8C9Fc41Aa1bB05b0c85A1';
const AERODROME_ROUTER = '0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43';
const AERODROME_FACTORY = '0x420DD381b31aEf6683db6B902084cB0FFECe40Da';
const WETH_BASE = '0x4200000000000000000000000000000000000006';

// ABIs for DEX operations
const ROUTER_ABI = [
  'function swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin, tuple(address from, address to, bool stable, address factory)[] routes, address to, uint256 deadline) external returns (uint256[] amounts)',
  'function getAmountsOut(uint256 amountIn, tuple(address from, address to, bool stable, address factory)[] routes) external view returns (uint256[] amounts)'
];

const ERC20_ABI = [
  'function approve(address spender, uint256 amount) external returns (bool)',
  'function balanceOf(address account) external view returns (uint256)',
  'function allowance(address owner, address spender) external view returns (uint256)'
];

// Scrypt parameters (MUST match contract)
const SCRYPT_N = 131072;  // 2^17
const SCRYPT_R = 8;
const SCRYPT_P = 1;
const SCRYPT_KEY_LEN = 32;

/**
 * Normalize an answer to match the contract's normalization.
 * - Lowercase
 * - Strip non-ASCII and punctuation (keep only a-z, 0-9, space)
 * - Collapse multiple spaces
 * - Trim
 *
 * @param {string} answer - The raw answer
 * @returns {string} - Normalized answer
 */
function normalize(answer) {
  return answer
    .toLowerCase()
    .replace(/[^a-z0-9 ]/g, '')  // Keep only a-z, 0-9, space
    .replace(/\s+/g, ' ')        // Collapse multiple spaces
    .trim();
}

/**
 * Derive scrypt key from a guess for a specific puzzle.
 *
 * @param {number} puzzleId - The puzzle ID
 * @param {string} guess - The normalized guess
 * @returns {Promise<Buffer>} - 32-byte key
 */
async function deriveKey(puzzleId, guess) {
  const salt = `ecash-v3-${puzzleId}`;
  const passwordBuffer = Buffer.from(guess, 'utf8');
  const saltBuffer = Buffer.from(salt, 'utf8');

  const key = await scrypt(passwordBuffer, saltBuffer, SCRYPT_N, SCRYPT_R, SCRYPT_P, SCRYPT_KEY_LEN);
  return Buffer.from(key);
}

/**
 * Try to decrypt a puzzle's blob with a guess.
 * Returns the decrypted data if successful, null otherwise.
 *
 * @param {number} puzzleId - The puzzle ID
 * @param {string} guess - The raw guess (will be normalized)
 * @param {object} blobData - Object with { blob, nonce, tag }
 * @returns {Promise<{success: boolean, data?: object, normalized: string}>}
 */
async function tryDecrypt(puzzleId, guess, blobData) {
  const normalized = normalize(guess);

  try {
    const key = await deriveKey(puzzleId, normalized);

    const ciphertext = Buffer.from(blobData.blob, 'hex');
    const nonce = Buffer.from(blobData.nonce, 'hex');
    const tag = Buffer.from(blobData.tag, 'hex');

    const decipher = crypto.createDecipheriv('aes-256-gcm', key, nonce);
    decipher.setAuthTag(tag);

    const decrypted = Buffer.concat([
      decipher.update(ciphertext),
      decipher.final()
    ]);

    const data = JSON.parse(decrypted.toString('utf8'));

    return {
      success: true,
      data,
      normalized
    };
  } catch (e) {
    return {
      success: false,
      normalized,
      error: e.message
    };
  }
}

/**
 * Compute the commit hash for the commit-reveal scheme.
 *
 * @param {string} answer - The normalized answer
 * @param {string} salt - The puzzle salt (bytes32 hex)
 * @param {string} secret - User's secret (bytes32 hex)
 * @param {string} address - User's address
 * @returns {string} - The commit hash (bytes32 hex)
 */
function computeCommitHash(answer, salt, secret, address) {
  // keccak256(abi.encodePacked(answer, salt, secret, msg.sender))
  const packed = ethers.solidityPacked(
    ['string', 'bytes32', 'bytes32', 'address'],
    [answer, salt, secret, address]
  );
  return ethers.keccak256(packed);
}

/**
 * Generate a random secret for commit-reveal.
 * @returns {string} - bytes32 hex string
 */
function generateSecret() {
  return '0x' + crypto.randomBytes(32).toString('hex');
}

/**
 * Create a new random wallet for mining.
 * @returns {object} - { address, privateKey, mnemonic }
 */
function createMinerWallet() {
  const wallet = ethers.Wallet.createRandom();
  return {
    address: wallet.address,
    privateKey: wallet.privateKey,
    mnemonic: wallet.mnemonic.phrase
  };
}

/**
 * Sell ECASH tokens for ETH on Aerodrome.
 * @param {ethers.Wallet} wallet - Connected wallet with ECASH balance
 * @param {string|bigint} amount - Amount to sell (string in ECASH units or bigint in wei)
 * @param {number} slippageBps - Slippage tolerance in basis points (default 500 = 5%)
 * @returns {Promise<object>} - { txHash, amountIn, expectedOut }
 */
async function sellEcash(wallet, amount, slippageBps = 500) {
  const amountIn = typeof amount === 'string' ? ethers.parseUnits(amount, 18) : amount;

  const ecash = new ethers.Contract(ECASH_ADDRESS, ERC20_ABI, wallet);
  const router = new ethers.Contract(AERODROME_ROUTER, ROUTER_ABI, wallet);

  const balance = await ecash.balanceOf(wallet.address);
  if (balance < amountIn) throw new Error('Insufficient ECASH balance');

  const routes = [{
    from: ECASH_ADDRESS,
    to: WETH_BASE,
    stable: false,
    factory: AERODROME_FACTORY
  }];

  const amountsOut = await router.getAmountsOut(amountIn, routes);
  const expectedOut = amountsOut[amountsOut.length - 1];
  const minOut = expectedOut * BigInt(10000 - slippageBps) / BigInt(10000);

  // Approve if needed
  const currentAllowance = await ecash.allowance(wallet.address, AERODROME_ROUTER);
  if (currentAllowance < amountIn) {
    const approveTx = await ecash.approve(AERODROME_ROUTER, amountIn);
    await approveTx.wait();
  }

  // Swap
  const deadline = Math.floor(Date.now() / 1000) + 1200;
  const swapTx = await router.swapExactTokensForETH(amountIn, minOut, routes, wallet.address, deadline);
  const receipt = await swapTx.wait();

  return {
    txHash: receipt.hash,
    amountIn: ethers.formatUnits(amountIn, 18),
    expectedOut: ethers.formatEther(expectedOut)
  };
}

/**
 * Get current ECASH price in ETH.
 * @param {ethers.Provider} provider - Ethers provider
 * @returns {Promise<object>} - { priceInETH, pricePerToken } or { error }
 */
async function getEcashPrice(provider) {
  const router = new ethers.Contract(AERODROME_ROUTER, ROUTER_ABI, provider);
  const routes = [{
    from: ECASH_ADDRESS,
    to: WETH_BASE,
    stable: false,
    factory: AERODROME_FACTORY
  }];

  try {
    const amounts = await router.getAmountsOut(ethers.parseUnits('1', 18), routes);
    return {
      priceInETH: ethers.formatEther(amounts[1]),
      pricePerToken: ethers.formatEther(amounts[1])
    };
  } catch (e) {
    return { error: 'No liquidity pool yet' };
  }
}

// Export functions
module.exports = {
  normalize,
  deriveKey,
  tryDecrypt,
  computeCommitHash,
  generateSecret,
  createMinerWallet,
  sellEcash,
  getEcashPrice,
  ECASH_ADDRESS,
  AERODROME_ROUTER,
  AERODROME_FACTORY,
  WETH_BASE,
  SCRYPT_N,
  SCRYPT_R,
  SCRYPT_P,
  SCRYPT_KEY_LEN
};

// Example usage when run directly
if (require.main === module) {
  (async () => {
    console.log('eCash SDK v3 - Example Usage\n');

    // Example: Normalize an answer
    const raw = "  Hello World!  ";
    const normalized = normalize(raw);
    console.log(`Normalize: "${raw}" -> "${normalized}"`);

    // Example: Generate a secret
    const secret = generateSecret();
    console.log(`\nGenerated secret: ${secret}`);

    // Example: Compute commit hash
    const answer = "example answer";
    const salt = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
    const address = "0x1234567890123456789012345678901234567890";
    const commitHash = computeCommitHash(answer, salt, secret, address);
    console.log(`\nCommit hash: ${commitHash}`);

    console.log('\n✓ SDK loaded successfully');
  })();
}
