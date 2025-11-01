import { verifyHmac, isTimestampFresh } from '../utils/hmac.js';

/**
 * Middleware to verify HMAC signature on incoming requests
 * Expects headers:
 * - X-Signature: HMAC signature (hex)
 * - X-Timestamp: Unix timestamp in milliseconds
 */
export function hmacVerification(req, res, next) {
  const signature = req.headers['x-signature'];
  const timestamp = parseInt(req.headers['x-timestamp'], 10);

  // Check required headers
  if (!signature) {
    return res.status(401).json({
      error: 'Unauthorized',
      message: 'Missing X-Signature header',
    });
  }

  if (!timestamp || isNaN(timestamp)) {
    return res.status(401).json({
      error: 'Unauthorized',
      message: 'Missing or invalid X-Timestamp header',
    });
  }

  // Check timestamp freshness (5 minute window)
  if (!isTimestampFresh(timestamp)) {
    return res.status(401).json({
      error: 'Unauthorized',
      message: 'Request timestamp is too old or in the future',
    });
  }

  // Verify HMAC signature
  if (!verifyHmac(signature, req.body, timestamp)) {
    return res.status(401).json({
      error: 'Unauthorized',
      message: 'Invalid signature',
    });
  }

  // Signature valid, proceed
  next();
}
