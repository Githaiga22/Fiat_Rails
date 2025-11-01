import { getDatabase } from '../database.js';
import { config } from '../config.js';
import { writeFileSync, readFileSync, existsSync, mkdirSync } from 'fs';
import { dirname } from 'path';

/**
 * Calculate next retry time using exponential backoff
 * @param {number} attempt - Current attempt number (0-indexed)
 * @returns {number} Milliseconds until next retry
 */
export function calculateBackoff(attempt) {
  const { initialBackoffMs, maxBackoffMs, backoffMultiplier } = config.retry;

  const backoff = initialBackoffMs * Math.pow(backoffMultiplier, attempt);
  return Math.min(backoff, maxBackoffMs);
}

/**
 * Add operation to retry queue
 * @param {string} intentId - Intent ID
 * @param {string} operation - Operation type ('execute' or 'refund')
 * @param {Object} payload - Operation payload
 */
export function addToRetryQueue(intentId, operation, payload) {
  const db = getDatabase();
  const now = Date.now();
  const nextRetryAt = now + calculateBackoff(0);

  db.prepare(
    `INSERT INTO retry_queue
     (intent_id, operation, payload, attempt, max_attempts, next_retry_at, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)`
  ).run(
    intentId,
    operation,
    JSON.stringify(payload),
    0,
    config.retry.maxAttempts,
    nextRetryAt,
    now
  );

  console.log(`Added to retry queue: ${operation} for intent ${intentId}`);
}

/**
 * Get items ready for retry
 * @returns {Array} Items ready to be retried
 */
export function getRetryableItems() {
  const db = getDatabase();
  const now = Date.now();

  return db
    .prepare(
      `SELECT * FROM retry_queue
       WHERE next_retry_at <= ? AND attempt < max_attempts
       ORDER BY next_retry_at ASC
       LIMIT 10`
    )
    .all(now);
}

/**
 * Update retry item after attempt
 * @param {number} id - Retry queue item ID
 * @param {boolean} success - Whether retry succeeded
 * @param {string} error - Error message if failed
 */
export function updateRetryItem(id, success, error = null) {
  const db = getDatabase();

  if (success) {
    // Remove from queue
    db.prepare('DELETE FROM retry_queue WHERE id = ?').run(id);
    console.log(`Retry succeeded, removed item ${id} from queue`);
  } else {
    // Increment attempt and schedule next retry
    const item = db.prepare('SELECT * FROM retry_queue WHERE id = ?').get(id);

    if (!item) return;

    const nextAttempt = item.attempt + 1;

    if (nextAttempt >= item.max_attempts) {
      // Max attempts reached, move to DLQ
      moveToDLQ(item, error);
      db.prepare('DELETE FROM retry_queue WHERE id = ?').run(id);
    } else {
      // Schedule next retry
      const nextRetryAt = Date.now() + calculateBackoff(nextAttempt);

      db.prepare(
        `UPDATE retry_queue
         SET attempt = ?, next_retry_at = ?, last_error = ?
         WHERE id = ?`
      ).run(nextAttempt, nextRetryAt, error, id);

      console.log(`Retry failed (attempt ${nextAttempt}/${item.max_attempts}), rescheduled item ${id}`);
    }
  }
}

/**
 * Move failed item to Dead Letter Queue
 * @param {Object} item - Retry queue item
 * @param {string} error - Final error message
 */
export function moveToDLQ(item, error) {
  // Ensure DLQ directory exists
  mkdirSync(dirname(config.dlq.path), { recursive: true });

  // Load existing DLQ
  let dlq = [];
  if (existsSync(config.dlq.path)) {
    dlq = JSON.parse(readFileSync(config.dlq.path, 'utf-8'));
  }

  // Add item to DLQ
  dlq.push({
    intentId: item.intent_id,
    operation: item.operation,
    payload: JSON.parse(item.payload),
    attempts: item.attempt,
    createdAt: item.created_at,
    failedAt: Date.now(),
    lastError: error || item.last_error,
  });

  // Write DLQ
  writeFileSync(config.dlq.path, JSON.stringify(dlq, null, 2));

  console.log(`Moved intent ${item.intent_id} to DLQ after ${item.attempt} attempts`);
}

/**
 * Process retry queue (called periodically)
 * @param {Function} processor - Async function to process each item
 */
export async function processRetryQueue(processor) {
  const items = getRetryableItems();

  for (const item of items) {
    try {
      const payload = JSON.parse(item.payload);
      await processor(item.operation, payload);
      updateRetryItem(item.id, true);
    } catch (error) {
      updateRetryItem(item.id, false, error.message);
    }
  }
}
