#!/usr/bin/env node

/**
 * Generate unique seed.json files for each candidate
 * 
 * Usage: node generate-seed.js <candidate-id> <output-path>
 * Example: node generate-seed.js CANDIDATE_042 ./candidate-042/seed.json
 * 
 * This ensures each candidate's implementation contains unique values
 * that prevent answer reuse between candidates.
 */

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

// Country codes to randomly assign
const COUNTRY_CODES = [
  { code: 'KES', name: 'Kenya Shilling Token', symbol: 'KES' },
  { code: 'NGN', name: 'Nigerian Naira Token', symbol: 'NGN' },
  { code: 'GHS', name: 'Ghanaian Cedi Token', symbol: 'GHS' },
  { code: 'UGX', name: 'Ugandan Shilling Token', symbol: 'UGX' },
  { code: 'TZS', name: 'Tanzanian Shilling Token', symbol: 'TZS' },
  { code: 'ZAR', name: 'South African Rand Token', symbol: 'ZAR' },
];

// Stablecoin options
const STABLECOINS = [
  { symbol: 'USDC', name: 'USD Coin' },
  { symbol: 'USDT', name: 'Tether USD' },
  { symbol: 'DAI', name: 'Dai Stablecoin' },
];

function generateRandomHex(bytes = 32) {
  return '0x' + crypto.randomBytes(bytes).toString('hex');
}

function generateSalt(prefix) {
  const random = crypto.randomBytes(8).toString('hex');
  return `${prefix}_${random}`;
}

function generateSeed(candidateId) {
  // Deterministic randomness based on candidate ID
  const seed = crypto.createHash('sha256').update(candidateId).digest();
  
  // Use seed for deterministic selection
  const countryIndex = seed[0] % COUNTRY_CODES.length;
  const stablecoinIndex = seed[1] % STABLECOINS.length;
  const chainId = 31337 + (seed[2] % 100);
  
  const country = COUNTRY_CODES[countryIndex];
  const stablecoin = STABLECOINS[stablecoinIndex];
  
  return {
    _comment: `Per-candidate unique seed for ${candidateId} - MUST use these values in your implementation`,
    candidateId: candidateId,
    chain: {
      chainId: chainId,
      rpcUrl: 'http://localhost:8545',
      blockTime: 2,
    },
    tokens: {
      stablecoin: {
        symbol: stablecoin.symbol,
        name: stablecoin.name,
        decimals: 18,
      },
      country: {
        symbol: country.symbol,
        name: country.name,
        countryCode: country.code,
        decimals: 18,
      },
    },
    secrets: {
      hmacSalt: generateSalt('fiatrails_hmac_salt'),
      idempotencyKeySalt: generateSalt('fiatrails_idem_salt'),
      mpesaWebhookSecret: generateSalt('mpesa_webhook_secret'),
    },
    compliance: {
      maxRiskScore: 50 + (seed[3] % 50), // 50-99
      requireAttestation: true,
      minAttestationAge: 0,
    },
    limits: {
      minMintAmount: '1000000000000000000', // 1 token
      maxMintAmount: '1000000000000000000000', // 1000 tokens
      dailyMintLimit: '10000000000000000000000', // 10000 tokens
    },
    retry: {
      maxAttempts: 3 + (seed[4] % 5), // 3-7
      initialBackoffMs: 500 + (seed[5] % 1500), // 500-2000ms
      maxBackoffMs: 30000,
      backoffMultiplier: 2,
    },
    timeouts: {
      rpcTimeoutMs: 20000 + (seed[6] % 20000), // 20-40s
      webhookTimeoutMs: 3000 + (seed[7] % 7000), // 3-10s
      idempotencyWindowSeconds: 86400, // 24h
    },
    validation: {
      checksumHash: generateRandomHex(8),
      configVersion: '1.0.0',
      generatedAt: new Date().toISOString(),
    },
  };
}

function main() {
  const args = process.argv.slice(2);
  
  if (args.length < 1) {
    console.error('Usage: node generate-seed.js <candidate-id> [output-path]');
    console.error('Example: node generate-seed.js CANDIDATE_042 ./output/seed.json');
    process.exit(1);
  }
  
  const candidateId = args[0];
  const outputPath = args[1] || `./seed-${candidateId}.json`;
  
  const seed = generateSeed(candidateId);
  
  // Ensure output directory exists
  const outputDir = path.dirname(outputPath);
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }
  
  // Write seed file
  fs.writeFileSync(outputPath, JSON.stringify(seed, null, 2));
  
  console.log(`✅ Generated seed for ${candidateId}`);
  console.log(`📁 Output: ${outputPath}`);
  console.log(`\nCandidate-specific values:`);
  console.log(`  - Chain ID: ${seed.chain.chainId}`);
  console.log(`  - Stablecoin: ${seed.tokens.stablecoin.symbol}`);
  console.log(`  - Country: ${seed.tokens.country.countryCode} (${seed.tokens.country.name})`);
  console.log(`  - Max Risk Score: ${seed.compliance.maxRiskScore}`);
  console.log(`  - Checksum: ${seed.validation.checksumHash}`);
}

if (require.main === module) {
  main();
}

module.exports = { generateSeed };

