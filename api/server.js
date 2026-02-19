const express = require('express');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const { ethers } = require('ethers');
const config = require('./config');
const abi = require('./abi.json');

const app = express();
app.use(cors());
app.use(express.json());

const limiter = rateLimit({
  windowMs: config.RATE_LIMIT.windowMs,
  max: config.RATE_LIMIT.max,
  message: { error: 'Too many requests, please try again later.' }
});
app.use(limiter);

// Load data files
let puzzles, blobs;
try {
  puzzles = require('./data/public-puzzles.json');
  blobs = require('./data/encrypted-blobs.json');
} catch (e) {
  console.error('Failed to load data files. Place public-puzzles.json and encrypted-blobs.json in ./data/');
  process.exit(1);
}

// Index blobs by puzzleId for quick lookup
const blobIndex = {};
blobs.forEach(b => blobIndex[b.puzzleId] = b);

// Contract setup
const provider = new ethers.JsonRpcProvider(config.RPC_URL);
const contract = new ethers.Contract(config.CONTRACT_ADDRESS, abi, provider);

// Cache for on-chain data
let statsCache = { data: null, timestamp: 0 };
let solvedCache = { data: new Map(), timestamp: 0 };
let leaderboardCache = { data: null, timestamp: 0 };

// Fetch leaderboard from PuzzleSolved events
async function getLeaderboard() {
  const now = Date.now();
  if (leaderboardCache.data && now - leaderboardCache.timestamp < config.CACHE_TTL) {
    return leaderboardCache.data;
  }

  // Query PuzzleSolved events from contract deployment block
  const DEPLOY_BLOCK = 29000000; // Approximate deploy block, adjust if needed
  const filter = contract.filters.PuzzleSolved();
  const events = await contract.queryFilter(filter, DEPLOY_BLOCK, 'latest');

  // Aggregate by solver
  const minerMap = new Map();
  for (const event of events) {
    const solver = event.args.solver;
    const reward = event.args.reward;

    if (!minerMap.has(solver)) {
      minerMap.set(solver, { address: solver, solves: 0, totalRewards: BigInt(0) });
    }
    const miner = minerMap.get(solver);
    miner.solves += 1;
    miner.totalRewards += reward;
  }

  // Convert to array and sort by solves descending
  const leaderboard = Array.from(minerMap.values())
    .map(m => ({
      address: m.address,
      solves: m.solves,
      totalRewards: ethers.formatEther(m.totalRewards)
    }))
    .sort((a, b) => b.solves - a.solves);

  leaderboardCache.data = leaderboard;
  leaderboardCache.timestamp = now;
  return leaderboard;
}

async function getStats() {
  const now = Date.now();
  if (statsCache.data && now - statsCache.timestamp < config.CACHE_TTL) {
    return statsCache.data;
  }

  const [totalSolved, miningReserve, era1End] = await Promise.all([
    contract.totalSolved(),
    contract.miningReserveBalance(),
    contract.ERA_1_END()
  ]);

  const currentEra = Number(totalSolved) < Number(era1End) ? 1 : 2;

  statsCache.data = {
    totalSolved: Number(totalSolved),
    miningReserve: ethers.formatEther(miningReserve),
    currentEra
  };
  statsCache.timestamp = now;
  return statsCache.data;
}

async function getSolvedStatus(puzzleIds) {
  const now = Date.now();
  const results = {};
  const toFetch = [];

  for (const id of puzzleIds) {
    if (solvedCache.data.has(id) && now - solvedCache.timestamp < config.CACHE_TTL) {
      results[id] = solvedCache.data.get(id);
    } else {
      toFetch.push(id);
    }
  }

  if (toFetch.length > 0) {
    const statuses = await Promise.all(toFetch.map(id => contract.puzzleSolved(id)));
    toFetch.forEach((id, i) => {
      const solved = statuses[i];
      results[id] = solved;
      solvedCache.data.set(id, solved);
    });
    solvedCache.timestamp = now;
  }

  return results;
}

// GET /health
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// GET /stats
app.get('/stats', async (req, res) => {
  try {
    const stats = await getStats();
    const leaderboard = await getLeaderboard();
    res.json({
      ...stats,
      totalMiners: leaderboard.length
    });
  } catch (e) {
    res.status(500).json({ error: 'Failed to fetch stats', details: e.message });
  }
});

// GET /leaderboard
app.get('/leaderboard', async (req, res) => {
  try {
    const leaderboard = await getLeaderboard();
    res.json({
      leaderboard,
      totalMiners: leaderboard.length
    });
  } catch (e) {
    res.status(500).json({ error: 'Failed to fetch leaderboard', details: e.message });
  }
});

// GET /contract
app.get('/contract', (req, res) => {
  res.json({
    address: config.CONTRACT_ADDRESS,
    chainId: config.CHAIN_ID,
    abi: abi
  });
});

// GET /puzzles
app.get('/puzzles', async (req, res) => {
  try {
    const page = Math.max(1, parseInt(req.query.page) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit) || 50));
    const start = (page - 1) * limit;
    const end = start + limit;

    const slice = puzzles.puzzles.slice(start, end);
    const ids = slice.map(p => p.id);
    const solvedStatus = await getSolvedStatus(ids);

    const result = slice.map(p => ({
      ...p,
      solved: solvedStatus[p.id] || false
    }));

    res.json({
      puzzles: result,
      pagination: {
        page,
        limit,
        total: puzzles.totalPuzzles,
        totalPages: Math.ceil(puzzles.totalPuzzles / limit)
      }
    });
  } catch (e) {
    res.status(500).json({ error: 'Failed to fetch puzzles', details: e.message });
  }
});

// GET /puzzles/:id
app.get('/puzzles/:id', async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    if (isNaN(id) || id < 0 || id >= puzzles.totalPuzzles) {
      return res.status(404).json({ error: 'Puzzle not found' });
    }

    const puzzle = puzzles.puzzles[id];
    const blob = blobIndex[id];
    const solvedStatus = await getSolvedStatus([id]);

    res.json({
      ...puzzle,
      solved: solvedStatus[id] || false,
      encryptedBlob: blob
    });
  } catch (e) {
    res.status(500).json({ error: 'Failed to fetch puzzle', details: e.message });
  }
});

// GET /puzzles/:id/blob
app.get('/puzzles/:id/blob', (req, res) => {
  const id = parseInt(req.params.id);
  if (isNaN(id) || id < 0 || id >= puzzles.totalPuzzles) {
    return res.status(404).json({ error: 'Puzzle not found' });
  }

  const blob = blobIndex[id];
  if (!blob) {
    return res.status(404).json({ error: 'Blob not found' });
  }

  res.json(blob);
});

// Start server
app.listen(config.PORT, () => {
  console.log(`eCash API running on port ${config.PORT}`);
  console.log(`Contract: ${config.CONTRACT_ADDRESS}`);
  console.log(`RPC: ${config.RPC_URL}`);
  console.log(`Puzzles loaded: ${puzzles.totalPuzzles}`);
});
