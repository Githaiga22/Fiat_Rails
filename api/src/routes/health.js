import { Router } from 'express';
import { register, Counter, Histogram, Gauge } from 'prom-client';
import { getDatabase } from '../database.js';
import { getBlockchain } from '../blockchain.js';

const router = Router();

// Prometheus metrics
export const metrics = {
  rpcRequests: new Counter({
    name: 'fiatrails_rpc_requests_total',
    help: 'Total number of RPC requests',
    labelNames: ['method', 'status'],
  }),

  mintIntents: new Counter({
    name: 'fiatrails_mint_intents_total',
    help: 'Total number of mint intents submitted',
    labelNames: ['status'],
  }),

  callbacks: new Counter({
    name: 'fiatrails_callbacks_total',
    help: 'Total number of M-PESA callbacks received',
    labelNames: ['status'],
  }),

  retries: new Counter({
    name: 'fiatrails_retries_total',
    help: 'Total number of retry attempts',
    labelNames: ['operation', 'status'],
  }),

  dlqDepth: new Gauge({
    name: 'fiatrails_dlq_depth',
    help: 'Number of items in Dead Letter Queue',
  }),

  queueDepth: new Gauge({
    name: 'fiatrails_retry_queue_depth',
    help: 'Number of items in retry queue',
  }),

  complianceChecks: new Counter({
    name: 'fiatrails_compliance_checks_total',
    help: 'Total number of compliance checks',
    labelNames: ['result'],
  }),

  rpcLatency: new Histogram({
    name: 'fiatrails_rpc_latency_seconds',
    help: 'RPC request latency in seconds',
    labelNames: ['method'],
    buckets: [0.1, 0.5, 1, 2, 5, 10],
  }),

  apiLatency: new Histogram({
    name: 'fiatrails_api_latency_seconds',
    help: 'API request latency in seconds',
    labelNames: ['endpoint', 'method'],
    buckets: [0.01, 0.05, 0.1, 0.5, 1, 2],
  }),
};

/**
 * GET /health
 * Health check endpoint
 */
router.get('/health', async (req, res) => {
  try {
    const health = {
      status: 'healthy',
      timestamp: Date.now(),
      checks: {},
    };

    // Check database
    try {
      const db = getDatabase();
      db.prepare('SELECT 1').get();
      health.checks.database = 'ok';
    } catch (error) {
      health.checks.database = 'error';
      health.status = 'degraded';
    }

    // Check RPC connectivity
    try {
      const { provider } = getBlockchain();
      await provider.getBlockNumber();
      health.checks.rpc = 'ok';
    } catch (error) {
      health.checks.rpc = 'error';
      health.status = 'degraded';
    }

    // Get queue depths
    try {
      const db = getDatabase();
      const queueDepth = db
        .prepare('SELECT COUNT(*) as count FROM retry_queue WHERE attempt < max_attempts')
        .get().count;

      health.checks.retryQueue = {
        status: 'ok',
        depth: queueDepth,
      };

      metrics.queueDepth.set(queueDepth);
    } catch (error) {
      health.checks.retryQueue = { status: 'error' };
    }

    const statusCode = health.status === 'healthy' ? 200 : 503;
    res.status(statusCode).json(health);
  } catch (error) {
    res.status(503).json({
      status: 'unhealthy',
      error: error.message,
    });
  }
});

/**
 * GET /metrics
 * Prometheus metrics endpoint
 */
router.get('/metrics', async (req, res) => {
  try {
    // Update queue depth gauge
    const db = getDatabase();
    const queueDepth = db
      .prepare('SELECT COUNT(*) as count FROM retry_queue WHERE attempt < max_attempts')
      .get().count;
    metrics.queueDepth.set(queueDepth);

    res.set('Content-Type', register.contentType);
    res.send(await register.metrics());
  } catch (error) {
    res.status(500).send(error.message);
  }
});

export default router;
