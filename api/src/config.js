import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Load seed.json for configuration values
const seedPath = join(__dirname, '../../seed.json');
const seed = JSON.parse(readFileSync(seedPath, 'utf-8'));

/**
 * Application configuration loaded from seed.json and environment variables
 */
export const config = {
  // Server
  port: process.env.PORT || 3000,
  nodeEnv: process.env.NODE_ENV || 'development',

  // Blockchain
  chain: {
    chainId: seed.chain.chainId,
    rpcUrl: process.env.RPC_URL || seed.chain.rpcUrl,
    blockTime: seed.chain.blockTime,
  },

  // Contracts (to be populated from deployments.json)
  contracts: {
    mintEscrow: process.env.MINT_ESCROW_ADDRESS || '',
    userRegistry: process.env.USER_REGISTRY_ADDRESS || '',
    usdStablecoin: process.env.USD_STABLECOIN_ADDRESS || '',
    countryToken: process.env.COUNTRY_TOKEN_ADDRESS || '',
  },

  // Private key for transaction signing
  executorPrivateKey: process.env.EXECUTOR_PRIVATE_KEY || '',

  // Secrets from seed.json
  secrets: {
    hmacSalt: seed.secrets.hmacSalt,
    idempotencyKeySalt: seed.secrets.idempotencyKeySalt,
    mpesaWebhookSecret: seed.secrets.mpesaWebhookSecret,
  },

  // Compliance rules
  compliance: {
    maxRiskScore: seed.compliance.maxRiskScore,
    requireAttestation: seed.compliance.requireAttestation,
    minAttestationAge: seed.compliance.minAttestationAge,
  },

  // Transaction limits
  limits: {
    minMintAmount: BigInt(seed.limits.minMintAmount),
    maxMintAmount: BigInt(seed.limits.maxMintAmount),
    dailyMintLimit: BigInt(seed.limits.dailyMintLimit),
  },

  // Retry configuration
  retry: {
    maxAttempts: seed.retry.maxAttempts,
    initialBackoffMs: seed.retry.initialBackoffMs,
    maxBackoffMs: seed.retry.maxBackoffMs,
    backoffMultiplier: seed.retry.backoffMultiplier,
  },

  // Timeouts
  timeouts: {
    rpcTimeoutMs: seed.timeouts.rpcTimeoutMs,
    webhookTimeoutMs: seed.timeouts.webhookTimeoutMs,
    idempotencyWindowSeconds: seed.timeouts.idempotencyWindowSeconds,
  },

  // Database
  database: {
    path: process.env.DB_PATH || './data/fiatrails.db',
  },

  // Dead Letter Queue
  dlq: {
    path: process.env.DLQ_PATH || './data/dlq.json',
  },
};

/**
 * Validate required configuration
 */
export function validateConfig() {
  const required = [
    { key: 'executorPrivateKey', value: config.executorPrivateKey },
    { key: 'contracts.mintEscrow', value: config.contracts.mintEscrow },
    { key: 'contracts.userRegistry', value: config.contracts.userRegistry },
    { key: 'contracts.usdStablecoin', value: config.contracts.usdStablecoin },
    { key: 'contracts.countryToken', value: config.contracts.countryToken },
  ];

  const missing = required.filter(({ value }) => !value);

  if (missing.length > 0) {
    const keys = missing.map(({ key }) => key).join(', ');
    throw new Error(`Missing required configuration: ${keys}`);
  }
}
