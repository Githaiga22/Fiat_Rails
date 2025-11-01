import { createHmac, timingSafeEqual } from 'crypto';
import { config } from '../config.js';

/**
 * Generate HMAC signature for a request
 * @param {Object} payload - Request payload
 * @param {number} timestamp - Unix timestamp in milliseconds
 * @returns {string} HMAC signature (hex)
 */
export function generateHmac(payload, timestamp) {
  const message = JSON.stringify(payload) + timestamp.toString();
  const hmac = createHmac('sha256', config.secrets.hmacSalt);
  hmac.update(message);
  return hmac.digest('hex');
}

/**
 * Verify HMAC signature
 * @param {string} signature - Provided signature
 * @param {Object} payload - Request payload
 * @param {number} timestamp - Request timestamp
 * @returns {boolean} True if signature is valid
 */
export function verifyHmac(signature, payload, timestamp) {
  const expected = generateHmac(payload, timestamp);

  // Use timing-safe comparison to prevent timing attacks
  try {
    const signatureBuffer = Buffer.from(signature, 'hex');
    const expectedBuffer = Buffer.from(expected, 'hex');

    if (signatureBuffer.length !== expectedBuffer.length) {
      return false;
    }

    return timingSafeEqual(signatureBuffer, expectedBuffer);
  } catch (error) {
    return false;
  }
}

/**
 * Check if timestamp is fresh (within acceptable window)
 * @param {number} timestamp - Unix timestamp in milliseconds
 * @param {number} maxAgeMs - Maximum age in milliseconds (default: 5 minutes)
 * @returns {boolean} True if timestamp is fresh
 */
export function isTimestampFresh(timestamp, maxAgeMs = 300000) {
  const now = Date.now();
  const age = now - timestamp;

  // Check if timestamp is in the past and not too old
  return age >= 0 && age <= maxAgeMs;
}
