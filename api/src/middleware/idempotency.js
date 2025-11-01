import { getDatabase } from '../database.js';
import { config } from '../config.js';

/**
 * Middleware to handle idempotency for POST requests
 * Expects header: X-Idempotency-Key
 */
export function idempotency(req, res, next) {
  const key = req.headers['x-idempotency-key'];

  if (!key) {
    return res.status(400).json({
      error: 'Bad Request',
      message: 'Missing X-Idempotency-Key header',
    });
  }

  const db = getDatabase();
  const now = Date.now();
  const expiresAt = now + (config.timeouts.idempotencyWindowSeconds * 1000);

  // Check if this key was used before
  const existing = db
    .prepare('SELECT * FROM idempotency_keys WHERE key = ?')
    .get(key);

  if (existing) {
    // Key exists - check if request completed
    if (existing.completed_at) {
      // Return cached response
      return res
        .status(existing.response_status)
        .json(JSON.parse(existing.response_body));
    } else {
      // Request in progress
      return res.status(409).json({
        error: 'Conflict',
        message: 'Request with this idempotency key is already in progress',
      });
    }
  }

  // Store new idempotency key
  const requestBody = JSON.stringify(req.body);
  db.prepare(
    `INSERT INTO idempotency_keys (key, request_body, created_at, expires_at)
     VALUES (?, ?, ?, ?)`
  ).run(key, requestBody, now, expiresAt);

  // Store original res.json to intercept response
  const originalJson = res.json.bind(res);

  // Override res.json to cache response
  res.json = function (body) {
    const responseBody = JSON.stringify(body);

    // Update idempotency record with response
    db.prepare(
      `UPDATE idempotency_keys
       SET response_status = ?, response_body = ?, completed_at = ?
       WHERE key = ?`
    ).run(res.statusCode, responseBody, Date.now(), key);

    // Call original json method
    return originalJson(body);
  };

  next();
}
