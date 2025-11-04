#!/usr/bin/env node

/**
 * FiatRails API Helper - HMAC-authenticated API client
 *
 * This script provides utility functions to interact with the FiatRails API
 * using proper HMAC authentication as defined in seed.json
 */

import crypto from 'crypto';
import fs from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { ethers } from 'ethers';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Load seed.json
const seedPath = join(__dirname, '..', 'seed.json');
const seed = JSON.parse(fs.readFileSync(seedPath, 'utf8'));

const API_BASE_URL = process.env.API_URL || 'http://localhost:3000';
const RPC_URL = process.env.RPC_URL || 'http://localhost:8545';
const HMAC_SECRET = seed.secrets.hmacSalt;
const WEBHOOK_SECRET = seed.secrets.mpesaWebhookSecret;

// Load deployments
const deploymentsPath = join(__dirname, '..', 'deployments.json');
let deployments;
try {
  deployments = JSON.parse(fs.readFileSync(deploymentsPath, 'utf8'));
} catch (e) {
  deployments = null;
}

/**
 * Generate HMAC signature for API request
 * @param {string} payload - Request body as JSON string
 * @param {number} timestamp - Unix timestamp in seconds
 * @param {string} secret - HMAC secret
 * @returns {string} HMAC signature in hex format
 */
function generateHmac(payload, timestamp, secret) {
  const message = `${timestamp}:${payload}`;
  return crypto.createHmac('sha256', secret).update(message).digest('hex');
}

/**
 * Submit a mint intent to the API
 * @param {Object} params
 * @param {string} params.userAddress - User's Ethereum address
 * @param {string} params.amount - Amount in wei (as string)
 * @param {string} params.transactionRef - Unique transaction reference
 * @param {string} params.idempotencyKey - Optional idempotency key (UUID)
 * @returns {Promise<Object>} API response
 */
export async function submitMintIntent({ userAddress, amount, transactionRef, idempotencyKey }) {
  const timestamp = Date.now(); // Milliseconds
  const body = {
    userAddress: userAddress,
    amount: amount,
    countryCode: seed.tokens.country.countryCode,
    txRef: transactionRef
  };

  const payload = JSON.stringify(body);
  // Match the API's HMAC format: JSON.stringify(payload) + timestamp
  const message = payload + timestamp.toString();
  const signature = crypto.createHmac('sha256', HMAC_SECRET).update(message).digest('hex');

  const headers = {
    'Content-Type': 'application/json',
    'X-Signature': signature,
    'X-Timestamp': timestamp.toString(),
    'X-Idempotency-Key': idempotencyKey || crypto.randomUUID()
  };

  const response = await fetch(`${API_BASE_URL}/mint-intents`, {
    method: 'POST',
    headers: headers,
    body: payload
  });

  const responseData = await response.json();

  return {
    status: response.status,
    ok: response.ok,
    data: responseData
  };
}

/**
 * Look up intentId from blockchain by txRef
 * @param {string} txRef - Transaction reference
 * @returns {Promise<string|null>} intentId or null if not found
 */
export async function getIntentIdByTxRef(txRef) {
  if (!deployments || !deployments.mintEscrow) {
    console.warn('No deployments.json found - cannot query blockchain');
    return null;
  }

  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const mintEscrow = new ethers.Contract(
    deployments.mintEscrow,
    [
      'event MintIntentSubmitted(bytes32 indexed intentId, address indexed user, uint256 amount, bytes32 indexed countryCode, bytes32 txRef)',
    ],
    provider
  );

  // Query for MintIntentSubmitted events with matching txRef
  const txRefBytes32 = ethers.encodeBytes32String(txRef);

  // Get events from the last 10000 blocks (adjust as needed)
  const currentBlock = await provider.getBlockNumber();
  const fromBlock = Math.max(0, currentBlock - 10000);

  const filter = mintEscrow.filters.MintIntentSubmitted();
  const events = await mintEscrow.queryFilter(filter, fromBlock, currentBlock);

  // Find event with matching txRef
  for (const event of events) {
    const eventTxRef = event.args[4]; // txRef is the 5th parameter (0-indexed)
    if (eventTxRef === txRefBytes32) {
      return event.args[0]; // intentId is the first parameter
    }
  }

  return null;
}

/**
 * Trigger M-PESA webhook callback
 * @param {Object} params
 * @param {string} params.transactionRef - Transaction reference from mint intent
 * @param {string} params.userAddress - User's Ethereum address
 * @param {string} params.amount - Amount in wei (as string)
 * @param {string} params.intentId - Optional intentId (will be looked up if not provided)
 * @returns {Promise<Object>} API response
 */
export async function triggerMpesaCallback({ transactionRef, userAddress, amount, intentId }) {
  const timestamp = Math.floor(Date.now() / 1000);

  // Look up intentId from blockchain if not provided
  if (!intentId) {
    console.log(`Looking up intentId for txRef: ${transactionRef}...`);
    intentId = await getIntentIdByTxRef(transactionRef);
    if (!intentId) {
      throw new Error(`No intent found for txRef: ${transactionRef}. Did you submit-intent first?`);
    }
    console.log(`Found intentId: ${intentId}`);
  }

  const body = {
    intentId: intentId,
    txRef: transactionRef,
    userAddress: userAddress,
    amount: amount
  };

  const payload = JSON.stringify(body);
  // Match the API's HMAC format: JSON.stringify(payload) + timestamp
  const message = payload + timestamp.toString();
  const signature = crypto.createHmac('sha256', WEBHOOK_SECRET).update(message).digest('hex');

  const headers = {
    'Content-Type': 'application/json',
    'X-Mpesa-Signature': signature,
    'X-Timestamp': timestamp.toString()
  };

  const response = await fetch(`${API_BASE_URL}/callbacks/mpesa`, {
    method: 'POST',
    headers: headers,
    body: payload
  });

  let responseData;
  try {
    responseData = await response.json();
  } catch (e) {
    responseData = { message: await response.text() };
  }

  return {
    status: response.status,
    ok: response.ok,
    data: responseData
  };
}

/**
 * Check API health
 * @returns {Promise<Object>} Health status
 */
export async function checkHealth() {
  const response = await fetch(`${API_BASE_URL}/health`);
  return await response.json();
}

/**
 * Get Prometheus metrics
 * @returns {Promise<string>} Metrics in Prometheus format
 */
export async function getMetrics() {
  const response = await fetch(`${API_BASE_URL}/metrics`);
  return await response.text();
}

// CLI usage
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const command = process.argv[2];

  if (command === 'submit-intent') {
    const userAddress = process.argv[3];
    const amount = process.argv[4];
    const txRef = process.argv[5] || `MPESA-${Date.now()}`;

    if (!userAddress || !amount) {
      console.error('Usage: api-helper.js submit-intent <userAddress> <amount> [txRef]');
      process.exit(1);
    }

    submitMintIntent({ userAddress, amount, transactionRef: txRef })
      .then(result => {
        console.log(JSON.stringify(result, null, 2));
        process.exit(result.ok ? 0 : 1);
      })
      .catch(err => {
        console.error('Error:', err.message);
        process.exit(1);
      });
  } else if (command === 'trigger-callback') {
    const txRef = process.argv[3];
    const userAddress = process.argv[4];
    const amount = process.argv[5];

    if (!txRef || !userAddress || !amount) {
      console.error('Usage: api-helper.js trigger-callback <txRef> <userAddress> <amount>');
      process.exit(1);
    }

    triggerMpesaCallback({ transactionRef: txRef, userAddress, amount })
      .then(result => {
        console.log(JSON.stringify(result, null, 2));
        process.exit(result.ok ? 0 : 1);
      })
      .catch(err => {
        console.error('Error:', err.message);
        process.exit(1);
      });
  } else if (command === 'health') {
    checkHealth()
      .then(result => {
        console.log(JSON.stringify(result, null, 2));
        process.exit(0);
      })
      .catch(err => {
        console.error('Error:', err.message);
        process.exit(1);
      });
  } else {
    console.log('FiatRails API Helper');
    console.log('');
    console.log('Commands:');
    console.log('  submit-intent <userAddress> <amount> [txRef]');
    console.log('  trigger-callback <txRef> <userAddress> <amount>');
    console.log('  health');
    console.log('');
    console.log('Examples:');
    console.log('  node api-helper.js submit-intent 0x123... 1000000000000000000 MPESA-123');
    console.log('  node api-helper.js trigger-callback MPESA-123 0x123... 1000000000000000000');
    console.log('  node api-helper.js health');
  }
}
