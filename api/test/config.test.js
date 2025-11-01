import { describe, it } from 'node:test';
import assert from 'node:assert';
import { config } from '../src/config.js';

describe('Configuration', () => {
  describe('seed.json values', () => {
    it('should load chain configuration from seed.json', () => {
      assert.strictEqual(config.chain.chainId, 31382);
      assert.strictEqual(config.chain.blockTime, 2);
    });

    it('should load secrets from seed.json', () => {
      assert.strictEqual(config.secrets.hmacSalt, 'fiatrails_hmac_salt_db0dec8bc76794ae');
      assert.strictEqual(config.secrets.idempotencyKeySalt, 'fiatrails_idem_salt_e2255b32f133aeee');
      assert.strictEqual(config.secrets.mpesaWebhookSecret, 'mpesa_webhook_secret_d3f23a70ddb53521');
    });

    it('should load compliance configuration', () => {
      assert.strictEqual(config.compliance.maxRiskScore, 83);
      assert.strictEqual(config.compliance.requireAttestation, true);
      assert.strictEqual(config.compliance.minAttestationAge, 0);
    });

    it('should load limits from seed.json', () => {
      assert.strictEqual(config.limits.minMintAmount.toString(), '1000000000000000000'); // 1e18
      assert.strictEqual(config.limits.maxMintAmount.toString(), '1000000000000000000000'); // 1e21
      assert.strictEqual(config.limits.dailyMintLimit.toString(), '10000000000000000000000'); // 1e22
    });

    it('should load retry configuration', () => {
      assert.strictEqual(config.retry.maxAttempts, 4);
      assert.strictEqual(config.retry.initialBackoffMs, 691);
      assert.strictEqual(config.retry.maxBackoffMs, 30000);
      assert.strictEqual(config.retry.backoffMultiplier, 2);
    });

    it('should load timeout configuration', () => {
      assert.strictEqual(config.timeouts.rpcTimeoutMs, 20178);
      assert.strictEqual(config.timeouts.webhookTimeoutMs, 3076);
      assert.strictEqual(config.timeouts.idempotencyWindowSeconds, 86400);
    });
  });

  describe('environment variables', () => {
    it('should use default port if not set', () => {
      // Port can be set via env or default to 3000
      assert.ok(typeof config.port === 'number');
      assert.ok(config.port > 0);
    });

    it('should have contract address configuration', () => {
      // Contract addresses are loaded from env (may be empty in test)
      assert.ok(typeof config.contracts.mintEscrow === 'string');
      assert.ok(typeof config.contracts.userRegistry === 'string');
      assert.ok(typeof config.contracts.usdStablecoin === 'string');
      assert.ok(typeof config.contracts.countryToken === 'string');
    });

    it('should load RPC URL from env or seed', () => {
      assert.ok(config.chain.rpcUrl);
      assert.ok(config.chain.rpcUrl.startsWith('http'));
    });
  });

  describe('data types', () => {
    it('should convert limits to BigInt', () => {
      assert.strictEqual(typeof config.limits.minMintAmount, 'bigint');
      assert.strictEqual(typeof config.limits.maxMintAmount, 'bigint');
      assert.strictEqual(typeof config.limits.dailyMintLimit, 'bigint');
    });

    it('should have correct numeric types', () => {
      assert.strictEqual(typeof config.chain.chainId, 'number');
      assert.strictEqual(typeof config.retry.maxAttempts, 'number');
      assert.strictEqual(typeof config.compliance.maxRiskScore, 'number');
    });

    it('should have correct boolean types', () => {
      assert.strictEqual(typeof config.compliance.requireAttestation, 'boolean');
    });
  });

  describe('database paths', () => {
    it('should have database path configured', () => {
      assert.ok(config.database.path);
      assert.ok(config.database.path.endsWith('.db'));
    });

    it('should have DLQ path configured', () => {
      assert.ok(config.dlq.path);
      assert.ok(config.dlq.path.endsWith('.json'));
    });
  });
});
