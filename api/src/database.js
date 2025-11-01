import Database from 'better-sqlite3';
import { mkdirSync } from 'fs';
import { dirname } from 'path';
import { config } from './config.js';

let db = null;

/**
 * Initialize database and create tables
 */
export function initDatabase() {
  // Create data directory if it doesn't exist
  mkdirSync(dirname(config.database.path), { recursive: true });

  // Open database connection
  db = new Database(config.database.path);
  db.pragma('journal_mode = WAL'); // Write-Ahead Logging for better concurrency

  // Create idempotency keys table
  db.exec(`
    CREATE TABLE IF NOT EXISTS idempotency_keys (
      key TEXT PRIMARY KEY,
      request_body TEXT NOT NULL,
      response_status INTEGER,
      response_body TEXT,
      created_at INTEGER NOT NULL,
      completed_at INTEGER,
      expires_at INTEGER NOT NULL
    )
  `);

  // Create index for expiration cleanup
  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_expires_at
    ON idempotency_keys(expires_at)
  `);

  // Create retry queue table
  db.exec(`
    CREATE TABLE IF NOT EXISTS retry_queue (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      intent_id TEXT NOT NULL,
      operation TEXT NOT NULL,
      payload TEXT NOT NULL,
      attempt INTEGER NOT NULL DEFAULT 0,
      max_attempts INTEGER NOT NULL,
      next_retry_at INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      last_error TEXT
    )
  `);

  // Create index for retry processing
  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_next_retry
    ON retry_queue(next_retry_at)
    WHERE attempt < max_attempts
  `);

  console.log('Database initialized:', config.database.path);
  return db;
}

/**
 * Get database instance
 */
export function getDatabase() {
  if (!db) {
    throw new Error('Database not initialized. Call initDatabase() first.');
  }
  return db;
}

/**
 * Close database connection
 */
export function closeDatabase() {
  if (db) {
    db.close();
    db = null;
  }
}

/**
 * Clean up expired idempotency keys
 */
export function cleanupExpiredKeys() {
  const now = Date.now();
  const stmt = db.prepare('DELETE FROM idempotency_keys WHERE expires_at < ?');
  const result = stmt.run(now);

  if (result.changes > 0) {
    console.log(`Cleaned up ${result.changes} expired idempotency keys`);
  }

  return result.changes;
}
