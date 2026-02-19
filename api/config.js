module.exports = {
  PORT: process.env.PORT || 3000,
  RPC_URL: process.env.RPC_URL || 'https://mainnet.base.org',
  CONTRACT_ADDRESS: '0x4fD4a91853ff9F9249c8C9Fc41Aa1bB05b0c85A1',
  CHAIN_ID: 8453,
  CACHE_TTL: 30000, // 30 seconds
  RATE_LIMIT: {
    windowMs: 60 * 1000, // 1 minute
    max: 100
  }
};
