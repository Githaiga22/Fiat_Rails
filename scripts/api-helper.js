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

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Load seed.json
const seedPath = join(__dirname, '..', 'seed.json');
const seed = JSON.parse(fs.readFileSync(seedPath, 'utf8'));

const API_BASE_URL = process.env.API_URL || 'http://localhost:3000';
const HMAC_SECRET = seed.secrets.hmacSalt;
const WEBHOOK_SECRET = seed.secrets.webhookSecret;

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
  const timestamp = Math.floor(Date.now() / 1000);
  const body = {
    userId: userAddress,
    amount: amount,
    countryCode: seed.tokens.country.countryCode,
    transactionRef: transactionRef
  };

  const payload = JSON.stringify(body);
  const signature = generateHmac(payload, timestamp, HMAC_SECRET);

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
 * Trigger M-PESA webhook callback
 * @param {Object} params
 * @param {string} params.transactionRef - Transaction reference from mint intent
 * @param {string} params.userAddress - User's Ethereum address
 * @param {string} params.amount - Amount in wei (as string)
 * @returns {Promise<Object>} API response
 */
export async function triggerMpesaCallback({ transactionRef, userAddress, amount }) {
  const timestamp = Math.floor(Date.now() / 1000);
  const body = {
    transactionRef: transactionRef,
    amount: amount,
    userId: userAddress,
    timestamp: timestamp * 1000 // milliseconds for webhook
  };

  const payload = JSON.stringify(body);
  const signature = generateHmac(payload, timestamp, WEBHOOK_SECRET);

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
