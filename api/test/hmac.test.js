import { describe, it } from 'node:test';
import assert from 'node:assert';
import { generateHmac, verifyHmac, isTimestampFresh } from '../src/utils/hmac.js';

describe('HMAC Utilities', () => {
  describe('generateHmac', () => {
    it('should generate consistent HMAC for same input', () => {
      const payload = { amount: '1000', country: 'KES' };
      const timestamp = 1234567890000;

      const hmac1 = generateHmac(payload, timestamp);
      const hmac2 = generateHmac(payload, timestamp);

      assert.strictEqual(hmac1, hmac2);
      assert.strictEqual(typeof hmac1, 'string');
      assert.strictEqual(hmac1.length, 64); // SHA256 hex is 64 chars
    });

    it('should generate different HMAC for different payloads', () => {
      const timestamp = 1234567890000;
      const payload1 = { amount: '1000' };
      const payload2 = { amount: '2000' };

      const hmac1 = generateHmac(payload1, timestamp);
      const hmac2 = generateHmac(payload2, timestamp);

      assert.notStrictEqual(hmac1, hmac2);
    });

    it('should generate different HMAC for different timestamps', () => {
      const payload = { amount: '1000' };
      const hmac1 = generateHmac(payload, 1000);
      const hmac2 = generateHmac(payload, 2000);

      assert.notStrictEqual(hmac1, hmac2);
    });
  });

  describe('verifyHmac', () => {
    it('should verify valid HMAC signature', () => {
      const payload = { amount: '1000', country: 'KES' };
      const timestamp = 1234567890000;
      const signature = generateHmac(payload, timestamp);

      const result = verifyHmac(signature, payload, timestamp);

      assert.strictEqual(result, true);
    });

    it('should reject invalid HMAC signature', () => {
      const payload = { amount: '1000' };
      const timestamp = 1234567890000;
      const invalidSignature = 'a'.repeat(64);

      const result = verifyHmac(invalidSignature, payload, timestamp);

      assert.strictEqual(result, false);
    });

    it('should reject HMAC with wrong payload', () => {
      const payload1 = { amount: '1000' };
      const payload2 = { amount: '2000' };
      const timestamp = 1234567890000;
      const signature = generateHmac(payload1, timestamp);

      const result = verifyHmac(signature, payload2, timestamp);

      assert.strictEqual(result, false);
    });

    it('should reject HMAC with wrong timestamp', () => {
      const payload = { amount: '1000' };
      const signature = generateHmac(payload, 1000);

      const result = verifyHmac(signature, payload, 2000);

      assert.strictEqual(result, false);
    });

    it('should handle malformed signatures gracefully', () => {
      const payload = { amount: '1000' };
      const timestamp = 1234567890000;

      assert.strictEqual(verifyHmac('not-hex', payload, timestamp), false);
      assert.strictEqual(verifyHmac('', payload, timestamp), false);
      assert.strictEqual(verifyHmac('abc', payload, timestamp), false);
    });
  });

  describe('isTimestampFresh', () => {
    it('should accept recent timestamp', () => {
      const now = Date.now();
      const recent = now - 60000; // 1 minute ago

      assert.strictEqual(isTimestampFresh(recent), true);
    });

    it('should reject old timestamp', () => {
      const now = Date.now();
      const old = now - 600000; // 10 minutes ago (default is 5 min)

      assert.strictEqual(isTimestampFresh(old), false);
    });

    it('should reject future timestamp', () => {
      const now = Date.now();
      const future = now + 60000; // 1 minute in future

      assert.strictEqual(isTimestampFresh(future), false);
    });

    it('should accept timestamp within custom window', () => {
      const now = Date.now();
      const recent = now - 500000; // 8.3 minutes ago

      // Should fail with default 5 min window
      assert.strictEqual(isTimestampFresh(recent), false);

      // Should pass with 10 min window
      assert.strictEqual(isTimestampFresh(recent, 600000), true);
    });

    it('should accept current timestamp', () => {
      const now = Date.now();

      assert.strictEqual(isTimestampFresh(now), true);
    });
  });
});
