import { describe, it } from 'node:test';
import assert from 'node:assert';
import { calculateBackoff } from '../src/services/retry.js';

describe('Retry System', () => {
  describe('calculateBackoff', () => {
    it('should return initial backoff for first attempt', () => {
      const backoff = calculateBackoff(0);
      assert.strictEqual(backoff, 691); // From seed.json
    });

    it('should double backoff for second attempt', () => {
      const backoff = calculateBackoff(1);
      assert.strictEqual(backoff, 691 * 2);
    });

    it('should quadruple backoff for third attempt', () => {
      const backoff = calculateBackoff(2);
      assert.strictEqual(backoff, 691 * 4);
    });

    it('should exponentially increase backoff', () => {
      const backoff0 = calculateBackoff(0);
      const backoff1 = calculateBackoff(1);
      const backoff2 = calculateBackoff(2);
      const backoff3 = calculateBackoff(3);

      assert.strictEqual(backoff1, backoff0 * 2);
      assert.strictEqual(backoff2, backoff0 * 4);
      assert.strictEqual(backoff3, backoff0 * 8);
    });

    it('should cap at max backoff of 30000ms', () => {
      const backoff = calculateBackoff(10); // Very high attempt
      assert.strictEqual(backoff, 30000); // Max from seed.json
    });

    it('should respect backoff multiplier of 2', () => {
      for (let i = 0; i < 5; i++) {
        const backoff = calculateBackoff(i);
        const expected = Math.min(691 * Math.pow(2, i), 30000);
        assert.strictEqual(backoff, expected);
      }
    });

    it('should handle edge case of attempt 0', () => {
      const backoff = calculateBackoff(0);
      assert.strictEqual(backoff, 691);
      assert.ok(backoff > 0);
    });

    it('should produce increasing sequence up to max', () => {
      let previous = 0;
      for (let i = 0; i < 10; i++) {
        const current = calculateBackoff(i);
        assert.ok(current >= previous);
        assert.ok(current <= 30000);
        previous = current;
      }
    });
  });
});
