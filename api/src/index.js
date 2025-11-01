import express from 'express';
import { config, validateConfig } from './config.js';
import { initDatabase, closeDatabase, cleanupExpiredKeys } from './database.js';
import { initBlockchain } from './blockchain.js';
import { processRetryQueue } from './services/retry.js';
import { executeMint } from './blockchain.js';

// Import routes
import mintIntentsRouter from './routes/mintIntents.js';
import callbacksRouter from './routes/callbacks.js';
import healthRouter from './routes/health.js';

const app = express();

// Middleware
app.use(express.json());

// Request logging
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = Date.now() - start;
    console.log(`${req.method} ${req.path} ${res.statusCode} ${duration}ms`);
  });
  next();
});

// Mount routes
app.use('/', mintIntentsRouter);
app.use('/', callbacksRouter);
app.use('/', healthRouter);

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    error: 'Not Found',
    message: `Route ${req.method} ${req.path} not found`,
  });
});

// Error handler
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({
    error: 'Internal Server Error',
    message: err.message,
  });
});

/**
 * Retry queue processor
 */
async function retryProcessor(operation, payload) {
  if (operation === 'execute') {
    await executeMint(payload.intentId);
  }
  // Add more operations as needed
}

/**
 * Start the server
 */
async function start() {
  try {
    console.log('FiatRails API starting...');

    // Validate configuration
    try {
      validateConfig();
    } catch (error) {
      console.error('Configuration validation failed:', error.message);
      console.error('Please set required environment variables or populate deployments.json');
      process.exit(1);
    }

    // Initialize database
    initDatabase();

    // Initialize blockchain
    initBlockchain();

    // Start Express server
    const server = app.listen(config.port, () => {
      console.log(`Server listening on port ${config.port}`);
      console.log(`Health check: http://localhost:${config.port}/health`);
      console.log(`Metrics: http://localhost:${config.port}/metrics`);
    });

    // Set up retry queue processor (every 5 seconds)
    const retryInterval = setInterval(async () => {
      try {
        await processRetryQueue(retryProcessor);
      } catch (error) {
        console.error('Error processing retry queue:', error);
      }
    }, 5000);

    // Set up cleanup of expired idempotency keys (every hour)
    const cleanupInterval = setInterval(() => {
      try {
        cleanupExpiredKeys();
      } catch (error) {
        console.error('Error cleaning up expired keys:', error);
      }
    }, 3600000);

    // Graceful shutdown
    const shutdown = async (signal) => {
      console.log(`\nReceived ${signal}, shutting down gracefully...`);

      clearInterval(retryInterval);
      clearInterval(cleanupInterval);

      server.close(() => {
        console.log('Server closed');
        closeDatabase();
        process.exit(0);
      });

      // Force shutdown after 10 seconds
      setTimeout(() => {
        console.error('Forced shutdown after timeout');
        process.exit(1);
      }, 10000);
    };

    process.on('SIGTERM', () => shutdown('SIGTERM'));
    process.on('SIGINT', () => shutdown('SIGINT'));
  } catch (error) {
    console.error('Failed to start server:', error);
    process.exit(1);
  }
}

// Start the application
start();
