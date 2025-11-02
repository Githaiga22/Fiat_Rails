#!/usr/bin/env node

/**
 * FiatRails End-to-End Test Suite
 *
 * This script tests the complete mint flow including:
 * - Mint intent submission
 * - M-PESA callback processing
 * - On-chain verification
 * - Idempotency protection
 * - Metrics collection
 */

import { submitMintIntent, triggerMpesaCallback, checkHealth, getMetrics } from './api-helper.js';
import { execSync } from 'child_process';
import crypto from 'crypto';
import fs from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Load deployments and seed
const deploymentsPath = join(__dirname, '..', 'deployments.json');
const deployments = JSON.parse(fs.readFileSync(deploymentsPath, 'utf8'));
const seedPath = join(__dirname, '..', 'seed.json');
const seed = JSON.parse(fs.readFileSync(seedPath, 'utf8'));

// Anvil default test accounts
const TEST_USER = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";
const RPC_URL = deployments.rpcUrl;

// Test counters
let testsPassed = 0;
let testsFailed = 0;

/**
 * Execute cast command and return output
 */
function castCall(contractAddress, signature, ...args) {
  const cmd = `cast call ${contractAddress} "${signature}" ${args.join(' ')} --rpc-url ${RPC_URL}`;
  try {
    return execSync(cmd, { encoding: 'utf8' }).trim();
  } catch (error) {
    console.error(`Cast call failed: ${error.message}`);
    return null;
  }
}

/**
 * Execute cast send and return transaction hash
 */
function castSend(contractAddress, signature, privateKey, ...args) {
  const cmd = `cast send ${contractAddress} "${signature}" ${args.join(' ')} --rpc-url ${RPC_URL} --private-key ${privateKey}`;
  try {
    return execSync(cmd, { encoding: 'utf8' }).trim();
  } catch (error) {
    console.error(`Cast send failed: ${error.message}`);
    return null;
  }
}

/**
 * Assert function for tests
 */
function assert(condition, testName, errorMessage) {
  if (condition) {
    console.log(`✅ PASS: ${testName}`);
    testsPassed++;
    return true;
  } else {
    console.log(`❌ FAIL: ${testName}`);
    if (errorMessage) console.log(`   ${errorMessage}`);
    testsFailed++;
    return false;
  }
}

/**
 * Test 1: Complete Mint Flow
 */
async function testCompleteMintFlow() {
  console.log('\n📋 Test 1: Complete Mint Flow');
  console.log('════════════════════════════════════════════════════════');

  const amount = '1000000000000000000'; // 1 token
  const txRef = `TEST-${crypto.randomUUID()}`;

  // Get initial balance
  const initialBalance = castCall(deployments.countryToken, 'balanceOf(address)(uint256)', TEST_USER);
  console.log(`Initial KES balance: ${initialBalance}`);

  // Step 1: Submit mint intent
  console.log('\n1. Submitting mint intent...');
  const intentResult = await submitMintIntent({
    userAddress: TEST_USER,
    amount: amount,
    transactionRef: txRef
  });

  assert(
    intentResult.ok && intentResult.status === 201,
    'Mint intent submission returns 201',
    `Status: ${intentResult.status}, Response: ${JSON.stringify(intentResult.data)}`
  );

  // Wait for intent to be processed
  await new Promise(resolve => setTimeout(resolve, 2000));

  // Step 2: Trigger M-PESA callback
  console.log('\n2. Triggering M-PESA callback...');
  const callbackResult = await triggerMpesaCallback({
    transactionRef: txRef,
    userAddress: TEST_USER,
    amount: amount
  });

  assert(
    callbackResult.ok && callbackResult.status === 200,
    'M-PESA callback processing returns 200',
    `Status: ${callbackResult.status}, Response: ${JSON.stringify(callbackResult.data)}`
  );

  // Wait for transaction to be mined
  await new Promise(resolve => setTimeout(resolve, 3000));

  // Step 3: Verify on-chain balance
  console.log('\n3. Verifying on-chain balance...');
  const finalBalance = castCall(deployments.countryToken, 'balanceOf(address)(uint256)', TEST_USER);
  console.log(`Final KES balance: ${finalBalance}`);

  const expectedBalance = BigInt(initialBalance) + BigInt(amount);
  assert(
    BigInt(finalBalance) === expectedBalance,
    'User received correct amount of KES tokens',
    `Expected: ${expectedBalance}, Got: ${finalBalance}`
  );
}

/**
 * Test 2: Idempotency Protection
 */
async function testIdempotency() {
  console.log('\n📋 Test 2: Idempotency Protection');
  console.log('════════════════════════════════════════════════════════');

  const amount = '500000000000000000'; // 0.5 tokens
  const txRef = `TEST-IDEM-${crypto.randomUUID()}`;
  const idempotencyKey = crypto.randomUUID();

  // Get initial balance
  const initialBalance = castCall(deployments.countryToken, 'balanceOf(address)(uint256)', TEST_USER);

  // Step 1: Submit first mint intent with idempotency key
  console.log('\n1. Submitting first mint intent with idempotency key...');
  const firstResult = await submitMintIntent({
    userAddress: TEST_USER,
    amount: amount,
    transactionRef: txRef,
    idempotencyKey: idempotencyKey
  });

  assert(
    firstResult.ok && firstResult.status === 201,
    'First request returns 201',
    `Status: ${firstResult.status}`
  );

  await new Promise(resolve => setTimeout(resolve, 1000));

  // Step 2: Submit duplicate request with same idempotency key
  console.log('\n2. Submitting duplicate request with same idempotency key...');
  const duplicateResult = await submitMintIntent({
    userAddress: TEST_USER,
    amount: amount,
    transactionRef: txRef,
    idempotencyKey: idempotencyKey
  });

  assert(
    duplicateResult.status === 200 || duplicateResult.status === 409,
    'Duplicate request returns 200 (cached) or 409 (in progress)',
    `Status: ${duplicateResult.status}, Response: ${JSON.stringify(duplicateResult.data)}`
  );

  // Trigger callback once
  console.log('\n3. Triggering M-PESA callback...');
  await triggerMpesaCallback({
    transactionRef: txRef,
    userAddress: TEST_USER,
    amount: amount
  });

  await new Promise(resolve => setTimeout(resolve, 3000));

  // Step 3: Verify only one mint occurred
  console.log('\n4. Verifying only one mint occurred...');
  const finalBalance = castCall(deployments.countryToken, 'balanceOf(address)(uint256)', TEST_USER);
  const expectedBalance = BigInt(initialBalance) + BigInt(amount);

  assert(
    BigInt(finalBalance) === expectedBalance,
    'Idempotency prevented double-mint',
    `Expected: ${expectedBalance}, Got: ${finalBalance}, Difference: ${BigInt(finalBalance) - expectedBalance}`
  );
}

/**
 * Test 3: Non-Compliant User Rejection
 */
async function testNonCompliantUser() {
  console.log('\n📋 Test 3: Non-Compliant User Rejection');
  console.log('════════════════════════════════════════════════════════');

  // Use a different account that is not compliant
  const nonCompliantUser = "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"; // Account #2
  const amount = '1000000000000000000';
  const txRef = `TEST-NONCOMPLIANT-${crypto.randomUUID()}`;

  // Get initial balance
  const initialBalance = castCall(deployments.countryToken, 'balanceOf(address)(uint256)', nonCompliantUser);

  // Submit intent (should succeed)
  console.log('\n1. Submitting mint intent for non-compliant user...');
  const intentResult = await submitMintIntent({
    userAddress: nonCompliantUser,
    amount: amount,
    transactionRef: txRef
  });

  assert(
    intentResult.ok && intentResult.status === 201,
    'Intent submission accepted (compliance check happens at execution)',
    `Status: ${intentResult.status}`
  );

  await new Promise(resolve => setTimeout(resolve, 2000));

  // Trigger callback (should fail compliance check)
  console.log('\n2. Triggering M-PESA callback (should fail compliance)...');
  const callbackResult = await triggerMpesaCallback({
    transactionRef: txRef,
    userAddress: nonCompliantUser,
    amount: amount
  });

  // Callback should process but mint should fail
  console.log(`Callback status: ${callbackResult.status}`);

  await new Promise(resolve => setTimeout(resolve, 3000));

  // Verify no mint occurred
  console.log('\n3. Verifying no mint occurred...');
  const finalBalance = castCall(deployments.countryToken, 'balanceOf(address)(uint256)', nonCompliantUser);

  assert(
    BigInt(finalBalance) === BigInt(initialBalance),
    'Non-compliant user did not receive tokens',
    `Initial: ${initialBalance}, Final: ${finalBalance}`
  );
}

/**
 * Test 4: Health and Metrics Endpoints
 */
async function testHealthAndMetrics() {
  console.log('\n📋 Test 4: Health and Metrics Endpoints');
  console.log('════════════════════════════════════════════════════════');

  // Test health endpoint
  console.log('\n1. Checking /health endpoint...');
  const health = await checkHealth();

  assert(
    health.status === 'healthy' || health.status === 'ok',
    'Health endpoint returns healthy status',
    `Response: ${JSON.stringify(health)}`
  );

  // Test metrics endpoint
  console.log('\n2. Checking /metrics endpoint...');
  const metrics = await getMetrics();

  assert(
    metrics.includes('fiatrails_') && metrics.includes('TYPE'),
    'Metrics endpoint returns Prometheus-formatted metrics',
    `Length: ${metrics.length} characters`
  );

  assert(
    metrics.includes('fiatrails_mint_intents_total') ||
    metrics.includes('fiatrails_rpc_requests_total'),
    'Metrics include business and technical counters',
    'Missing expected metric names'
  );

  console.log(`\n   Metrics include:`);
  console.log(`   - RPC metrics: ${metrics.includes('fiatrails_rpc')}`);
  console.log(`   - Mint metrics: ${metrics.includes('fiatrails_mint')}`);
  console.log(`   - Callback metrics: ${metrics.includes('fiatrails_callbacks')}`);
}

/**
 * Main test runner
 */
async function runTests() {
  console.log('');
  console.log('════════════════════════════════════════════════════════');
  console.log('       FiatRails End-to-End Test Suite');
  console.log('════════════════════════════════════════════════════════');
  console.log('');
  console.log(`Network: ${deployments.network}`);
  console.log(`Chain ID: ${deployments.chainId}`);
  console.log(`RPC URL: ${deployments.rpcUrl}`);
  console.log('');

  try {
    await testCompleteMintFlow();
    await testIdempotency();
    await testNonCompliantUser();
    await testHealthAndMetrics();

    // Test summary
    console.log('');
    console.log('════════════════════════════════════════════════════════');
    console.log('                  TEST SUMMARY');
    console.log('════════════════════════════════════════════════════════');
    console.log(`Total Tests: ${testsPassed + testsFailed}`);
    console.log(`✅ Passed: ${testsPassed}`);
    console.log(`❌ Failed: ${testsFailed}`);
    console.log('');

    if (testsFailed === 0) {
      console.log('🎉 All tests passed!');
      process.exit(0);
    } else {
      console.log('⚠️  Some tests failed. Please review the output above.');
      process.exit(1);
    }
  } catch (error) {
    console.error('\n❌ Test suite failed with error:', error.message);
    console.error(error.stack);
    process.exit(1);
  }
}

// Run tests
runTests();
