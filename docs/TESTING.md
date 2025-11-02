# FiatRails Testing Guide

**Version:** 1.0
**Last Updated:** 2025-11-02

---

## Overview

This document describes the testing strategy for FiatRails, including automated tests and manual testing procedures for scenarios that require operator intervention.

---

## Table of Contents

1. [Automated Tests](#automated-tests)
2. [Manual Testing Procedures](#manual-testing-procedures)
3. [Failure Scenario Simulations](#failure-scenario-simulations)
4. [Performance Testing](#performance-testing)
5. [Security Testing](#security-testing)

---

## Automated Tests

### Smart Contract Tests

**Location:** `contracts/test/`

**Run All Tests:**
```bash
cd contracts
forge test
```

**With Verbosity:**
```bash
forge test -vvv
```

**Test Coverage:**
```bash
forge coverage
```

**Current Coverage:** 94.26% (Target: >80%)

**Test Categories:**
- Unit tests: Individual contract functions
- Integration tests: Multi-contract interactions
- Fuzz tests: Random input validation
- Upgrade tests: Proxy upgrade mechanisms

**Key Test Files:**
- `CountryToken.t.sol` - ERC20 token minting
- `UserRegistry.t.sol` - Compliance and risk scoring
- `ComplianceManager.t.sol` - UUPS upgrades and access control
- `MintEscrow.t.sol` - Complete mint flow and idempotency
- `IntegrationTest.t.sol` - End-to-end flows

### API Tests

**Location:** `api/test/`

**Run All Tests:**
```bash
cd api
npm test
```

**With Coverage:**
```bash
npm run test:coverage
```

**Test Categories:**
- HMAC verification tests (13 tests)
- Exponential backoff tests (8 tests)
- Idempotency tests
- Endpoint tests (mint-intents, callbacks)
- Metrics tests

### End-to-End Tests

**Location:** `scripts/e2e-test.js`

**Run E2E Tests:**
```bash
# Prerequisites: Docker services must be running
docker compose up -d

# Wait for services to be ready
sleep 10

# Run E2E test suite
node scripts/e2e-test.js
```

**Test Scenarios:**
1. **Complete Mint Flow** - Intent submission → callback → on-chain verification
2. **Idempotency Protection** - Duplicate requests with same key
3. **Non-Compliant User Rejection** - Compliance enforcement
4. **Health and Metrics** - Monitoring endpoints

---

## Manual Testing Procedures

### Why Manual Testing?

Some failure scenarios require external system manipulation that cannot be easily automated:
- RPC provider failures
- Network timeouts
- Retry exhaustion scenarios
- Dead-letter queue processing

### Prerequisites

1. **Running System:**
   ```bash
   ./scripts/deploy-and-demo.sh
   # Services running on:
   # - API: http://localhost:3000
   # - Anvil: http://localhost:8545
   # - Prometheus: http://localhost:9090
   # - Grafana: http://localhost:3001
   ```

2. **Test Accounts:**
   - Deployer: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
   - Test User: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8

3. **Monitoring:**
   - Open Grafana dashboard: http://localhost:3001 (admin/admin)
   - Open terminal with API logs: `docker logs -f fiatrails-api`

---

### Manual Test 1: RPC Failure and Retry Logic

**Objective:** Verify that the API properly retries failed RPC calls with exponential backoff.

**Procedure:**

1. **Setup - Submit a mint intent:**
   ```bash
   TX_REF="TEST-RETRY-$(date +%s)"
   AMOUNT="1000000000000000000"
   TEST_USER="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"

   node scripts/api-helper.js submit-intent $TEST_USER $AMOUNT $TX_REF
   ```

2. **Simulate RPC failure by stopping Anvil:**
   ```bash
   docker compose stop anvil
   ```

3. **Trigger M-PESA callback (should fail):**
   ```bash
   node scripts/api-helper.js trigger-callback $TX_REF $TEST_USER $AMOUNT
   ```

4. **Observe retry behavior:**
   ```bash
   # Watch API logs for retry attempts
   docker logs -f fiatrails-api | grep -E "(retry|backoff|attempt)"
   ```

5. **Expected Behavior:**
   - First attempt: Immediate failure (RPC unavailable)
   - Retry 1: After ~691ms
   - Retry 2: After ~1382ms (2x backoff)
   - Retry 3: After ~2764ms (2x backoff)
   - Retry 4: After ~5528ms (2x backoff)
   - Retry 5: After ~11056ms (2x backoff)
   - After max retries: Item moved to DLQ

6. **Check Prometheus metrics:**
   ```bash
   # Query retry count
   curl -s 'http://localhost:9090/api/v1/query?query=fiatrails_retries_total' | jq .
   ```

7. **Restore RPC:**
   ```bash
   docker compose start anvil
   sleep 5
   ```

8. **Verify DLQ item created:**
   ```bash
   # Check DLQ directory
   ls -la api/dlq/
   cat api/dlq/*.json | jq .
   ```

9. **Expected DLQ Item Structure:**
   ```json
   {
     "operation": "executeMint",
     "intentId": "TEST-RETRY-...",
     "attempts": 5,
     "lastError": "RPC connection failed",
     "timestamp": "2025-11-02T...",
     "payload": {
       "transactionRef": "TEST-RETRY-...",
       "amount": "1000000000000000000",
       "userId": "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
     }
   }
   ```

**Success Criteria:**
- ✅ API attempts retries with exponential backoff
- ✅ Backoff intervals match configured values (691ms initial, 2x multiplier, max 30s)
- ✅ After 5 failed attempts, item moved to DLQ
- ✅ Metrics show retry counts incrementing
- ✅ API remains responsive during retry attempts

---

### Manual Test 2: Dead-Letter Queue Processing

**Objective:** Verify DLQ items can be manually replayed after system recovery.

**Procedure:**

1. **Prerequisites - Create DLQ item from Manual Test 1:**
   - Complete Manual Test 1 to generate a DLQ item
   - Ensure Anvil is now running

2. **Inspect DLQ contents:**
   ```bash
   ls -la api/dlq/
   DLQ_FILE=$(ls api/dlq/*.json | head -1)
   cat $DLQ_FILE | jq .
   ```

3. **Note the intent details:**
   ```bash
   TX_REF=$(cat $DLQ_FILE | jq -r '.payload.transactionRef')
   USER_ADDR=$(cat $DLQ_FILE | jq -r '.payload.userId')
   AMOUNT=$(cat $DLQ_FILE | jq -r '.payload.amount')

   echo "Transaction Ref: $TX_REF"
   echo "User Address: $USER_ADDR"
   echo "Amount: $AMOUNT"
   ```

4. **Get user's initial KES balance:**
   ```bash
   # Load deployments
   COUNTRY_TOKEN=$(cat deployments.json | jq -r '.countryToken')

   # Check balance
   INITIAL_BALANCE=$(cast call $COUNTRY_TOKEN "balanceOf(address)(uint256)" $USER_ADDR --rpc-url http://localhost:8545)
   echo "Initial KES balance: $INITIAL_BALANCE"
   ```

5. **Manually replay the callback:**
   ```bash
   node scripts/api-helper.js trigger-callback $TX_REF $USER_ADDR $AMOUNT
   ```

6. **Expected Response:**
   ```json
   {
     "status": 200,
     "ok": true,
     "data": {
       "message": "Callback processed successfully"
     }
   }
   ```

7. **Verify mint executed on-chain:**
   ```bash
   # Check new balance
   FINAL_BALANCE=$(cast call $COUNTRY_TOKEN "balanceOf(address)(uint256)" $USER_ADDR --rpc-url http://localhost:8545)
   echo "Final KES balance: $FINAL_BALANCE"

   # Calculate difference
   EXPECTED=$(echo "$INITIAL_BALANCE + $AMOUNT" | bc)
   echo "Expected: $EXPECTED"

   if [ "$FINAL_BALANCE" = "$EXPECTED" ]; then
       echo "✅ Mint successful!"
   else
       echo "❌ Balance mismatch"
   fi
   ```

8. **Verify DLQ cleanup (optional - manual step):**
   ```bash
   # In production, DLQ items should be archived after successful replay
   # For now, manually move to archive folder:
   mkdir -p api/dlq/archive
   mv api/dlq/*.json api/dlq/archive/
   ```

9. **Check Grafana dashboard:**
   - Open http://localhost:3001
   - Navigate to FiatRails dashboard
   - Verify "DLQ Depth" panel shows count decreased

**Success Criteria:**
- ✅ DLQ item contains all necessary information for replay
- ✅ Manual replay succeeds after system recovery
- ✅ On-chain state updated correctly (balance increased)
- ✅ Idempotency prevents double-minting if replayed twice
- ✅ Metrics reflect successful replay

---

### Manual Test 3: Idempotency with Network Failures

**Objective:** Verify idempotency works even during network interruptions.

**Procedure:**

1. **Generate unique keys:**
   ```bash
   IDEMPOTENCY_KEY=$(uuidgen)
   TX_REF="TEST-IDEM-$(date +%s)"
   AMOUNT="500000000000000000"
   TEST_USER="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"

   echo "Idempotency Key: $IDEMPOTENCY_KEY"
   echo "Transaction Ref: $TX_REF"
   ```

2. **Submit first request with idempotency key:**
   ```bash
   # Modify api-helper.js call to include idempotency key
   # Or use curl:
   TIMESTAMP=$(date +%s)
   BODY=$(cat <<EOF
{
  "userId": "$TEST_USER",
  "amount": "$AMOUNT",
  "countryCode": "KES",
  "transactionRef": "$TX_REF"
}
EOF
)

   # Generate HMAC (read secret from seed.json)
   HMAC_SECRET=$(cat seed.json | jq -r '.secrets.hmacSalt')
   MESSAGE="$TIMESTAMP:$BODY"
   SIGNATURE=$(echo -n "$MESSAGE" | openssl dgst -sha256 -hmac "$HMAC_SECRET" -binary | xxd -p -c 256)

   # Submit request
   curl -X POST http://localhost:3000/mint-intents \
     -H "Content-Type: application/json" \
     -H "X-Signature: $SIGNATURE" \
     -H "X-Timestamp: $TIMESTAMP" \
     -H "X-Idempotency-Key: $IDEMPOTENCY_KEY" \
     -d "$BODY"
   ```

3. **Immediately submit duplicate request (within processing window):**
   ```bash
   # Wait 100ms
   sleep 0.1

   # Submit exact same request with same idempotency key
   curl -X POST http://localhost:3000/mint-intents \
     -H "Content-Type: application/json" \
     -H "X-Signature: $SIGNATURE" \
     -H "X-Timestamp: $TIMESTAMP" \
     -H "X-Idempotency-Key: $IDEMPOTENCY_KEY" \
     -d "$BODY"
   ```

4. **Expected Responses:**
   - First request: `201 Created` with intent ID
   - Second request: `200 OK` (cached) or `409 Conflict` (in progress)

5. **Trigger callback once:**
   ```bash
   node scripts/api-helper.js trigger-callback $TX_REF $TEST_USER $AMOUNT
   ```

6. **Verify only one mint occurred:**
   ```bash
   COUNTRY_TOKEN=$(cat deployments.json | jq -r '.countryToken')
   BALANCE=$(cast call $COUNTRY_TOKEN "balanceOf(address)(uint256)" $TEST_USER --rpc-url http://localhost:8545)
   echo "User balance: $BALANCE"
   # Should be exactly $AMOUNT more than before, not 2x
   ```

**Success Criteria:**
- ✅ First request returns 201
- ✅ Duplicate request returns 200 or 409 (not 201)
- ✅ Only one mint executed on-chain
- ✅ Idempotency key stored in database with TTL
- ✅ After TTL (24h), same key can be reused

---

### Manual Test 4: Compliance Check During Callback

**Objective:** Verify non-compliant users cannot mint even if intent was accepted.

**Procedure:**

1. **Setup non-compliant user:**
   ```bash
   NON_COMPLIANT_USER="0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"  # Anvil Account #2
   USER_REGISTRY=$(cat deployments.json | jq -r '.userRegistry')

   # Set high risk score (above threshold of 83)
   RISK_SCORE=90
   ATTESTATION="0xbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadb"

   cast send $USER_REGISTRY "updateUser(address,uint8,bytes32,bool)" \
     $NON_COMPLIANT_USER $RISK_SCORE $ATTESTATION true \
     --rpc-url http://localhost:8545 \
     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
   ```

2. **Verify user is non-compliant:**
   ```bash
   IS_COMPLIANT=$(cast call $USER_REGISTRY "isCompliant(address)(bool)" $NON_COMPLIANT_USER --rpc-url http://localhost:8545)
   echo "User compliant: $IS_COMPLIANT"  # Should be "false"
   ```

3. **Pre-mint USD to non-compliant user:**
   ```bash
   USD_STABLECOIN=$(cat deployments.json | jq -r '.usdStablecoin')
   MINT_AMOUNT="10000000000000000000"  # 10 USDT

   cast send $USD_STABLECOIN "mint(address,uint256)" $NON_COMPLIANT_USER $MINT_AMOUNT \
     --rpc-url http://localhost:8545 \
     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
   ```

4. **Approve MintEscrow:**
   ```bash
   MINT_ESCROW=$(cat deployments.json | jq -r '.mintEscrow')
   NON_COMPLIANT_KEY="0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"  # Account #2 key

   cast send $USD_STABLECOIN "approve(address,uint256)" $MINT_ESCROW "1000000000000000000" \
     --rpc-url http://localhost:8545 \
     --private-key $NON_COMPLIANT_KEY
   ```

5. **Submit mint intent (should succeed):**
   ```bash
   TX_REF="TEST-NONCOMPLIANT-$(date +%s)"
   AMOUNT="1000000000000000000"

   node scripts/api-helper.js submit-intent $NON_COMPLIANT_USER $AMOUNT $TX_REF
   ```

6. **Get initial balance:**
   ```bash
   COUNTRY_TOKEN=$(cat deployments.json | jq -r '.countryToken')
   INITIAL_BALANCE=$(cast call $COUNTRY_TOKEN "balanceOf(address)(uint256)" $NON_COMPLIANT_USER --rpc-url http://localhost:8545)
   echo "Initial balance: $INITIAL_BALANCE"
   ```

7. **Trigger callback (should fail compliance check):**
   ```bash
   node scripts/api-helper.js trigger-callback $TX_REF $NON_COMPLIANT_USER $AMOUNT
   ```

8. **Expected Response:**
   ```json
   {
     "status": 200,
     "ok": true,
     "data": {
       "message": "Callback received"
     }
   }
   ```
   Note: Callback may return 200 but mint execution fails internally

9. **Verify no mint occurred:**
   ```bash
   sleep 3
   FINAL_BALANCE=$(cast call $COUNTRY_TOKEN "balanceOf(address)(uint256)" $NON_COMPLIANT_USER --rpc-url http://localhost:8545)
   echo "Final balance: $FINAL_BALANCE"

   if [ "$FINAL_BALANCE" = "$INITIAL_BALANCE" ]; then
       echo "✅ Compliance check working! Non-compliant user did not receive tokens"
   else
       echo "❌ SECURITY ISSUE: Non-compliant user received tokens!"
   fi
   ```

10. **Check API logs for compliance failure:**
    ```bash
    docker logs fiatrails-api | grep -i "compliance"
    # Should show: "User not compliant" or similar message
    ```

**Success Criteria:**
- ✅ Intent submission accepted (compliance checked at execution, not submission)
- ✅ Callback processed but mint failed
- ✅ Non-compliant user balance unchanged
- ✅ Logs show compliance check failure
- ✅ Metrics show failed mint attempt

---

## Failure Scenario Simulations

### Simulating RPC Timeout

```bash
# Add latency to RPC calls
docker compose stop anvil
docker compose up -d anvil --scale anvil=1 --force-recreate

# Or use network delay tools:
tc qdisc add dev eth0 root netem delay 5000ms
```

### Simulating Database Failure

```bash
# Stop database
docker compose stop postgres  # or sqlite file permissions

# API should handle gracefully and return 503
curl http://localhost:3000/mint-intents
# Expected: 503 Service Unavailable
```

### Simulating HMAC Forgery Attack

```bash
# Submit request with invalid signature
curl -X POST http://localhost:3000/mint-intents \
  -H "Content-Type: application/json" \
  -H "X-Signature: invalidhexstring" \
  -H "X-Timestamp: $(date +%s)" \
  -H "X-Idempotency-Key: $(uuidgen)" \
  -d '{"userId":"0x123...","amount":"1000","countryCode":"KES","transactionRef":"TEST"}'

# Expected: 401 Unauthorized or 403 Forbidden
```

### Simulating Stale Timestamp Attack

```bash
# Submit request with old timestamp (>5 minutes old)
OLD_TIMESTAMP=$(($(date +%s) - 400))  # 400 seconds ago

curl -X POST http://localhost:3000/mint-intents \
  -H "Content-Type: application/json" \
  -H "X-Signature: <valid-hmac-for-old-timestamp>" \
  -H "X-Timestamp: $OLD_TIMESTAMP" \
  -H "X-Idempotency-Key: $(uuidgen)" \
  -d '{"userId":"0x123...","amount":"1000","countryCode":"KES","transactionRef":"TEST"}'

# Expected: 401 Unauthorized (timestamp too old)
```

---

## Performance Testing

### Load Testing with `k6`

**Install k6:**
```bash
# macOS
brew install k6

# Linux
sudo apt install k6
```

**Create load test script (`api/test/load-test.js`):**
```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  stages: [
    { duration: '1m', target: 10 },   // Ramp up to 10 users
    { duration: '3m', target: 10 },   // Stay at 10 users
    { duration: '1m', target: 50 },   // Ramp up to 50 users
    { duration: '3m', target: 50 },   // Stay at 50 users
    { duration: '1m', target: 0 },    // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],  // 95% of requests < 500ms
    http_req_failed: ['rate<0.05'],    // Error rate < 5%
  },
};

export default function () {
  const res = http.get('http://localhost:3000/health');
  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });
  sleep(1);
}
```

**Run load test:**
```bash
k6 run api/test/load-test.js
```

**Success Criteria:**
- p95 latency < 500ms
- Error rate < 5%
- System remains stable under load

---

## Security Testing

### HMAC Verification Tests

Run security-focused unit tests:
```bash
cd api
npm test -- hmac.test.js
```

### Smart Contract Security Tests

```bash
cd contracts
forge test --match-test "testFail|testRevert"
```

### Static Analysis

```bash
# Solidity
forge fmt --check
slither .

# JavaScript
npm run lint
npm audit
```

---

## Continuous Testing

### Pre-Commit Hooks

Add to `.git/hooks/pre-commit`:
```bash
#!/bin/bash
set -e

# Run contract tests
cd contracts && forge test

# Run API tests
cd ../api && npm test

# Check formatting
forge fmt --check
npm run lint
```

### CI/CD Pipeline

See `.github/workflows/ci.yml` for automated testing on every push.

---

## Test Data Management

### Seed Test Users

```bash
# Always use Anvil default accounts for consistency
ACCOUNT_0="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"  # Deployer
ACCOUNT_1="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"  # Compliant user
ACCOUNT_2="0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"  # Non-compliant user
```

### Reset Test Environment

```bash
# Complete reset
docker compose down -v
rm -rf api/dlq/*.json
rm -rf api/data/*.db

# Fresh start
./scripts/deploy-and-demo.sh
```

---

## Troubleshooting Test Failures

### Contract Tests Failing

```bash
# Run with maximum verbosity
forge test -vvvv

# Run specific test
forge test --match-test testMintFlow -vvv

# Check gas usage
forge snapshot
```

### API Tests Failing

```bash
# Run with debug output
DEBUG=* npm test

# Run specific test file
npm test -- hmac.test.js

# Check service logs
docker logs fiatrails-api
```

### E2E Tests Failing

```bash
# Check services are running
docker compose ps

# Check deployments.json exists
cat deployments.json

# Check Anvil is accessible
cast block-number --rpc-url http://localhost:8545

# Check API is accessible
curl http://localhost:3000/health
```

---

## Test Metrics Tracking

Track test execution metrics over time:

| Date | Contract Tests | API Tests | E2E Tests | Coverage | Duration |
|------|---------------|-----------|-----------|----------|----------|
| 2025-11-02 | 107 passing | 35 passing | 12 passing | 94.26% | 8.2s |

---

## Future Testing Enhancements

- [ ] Add chaos engineering tests (random failures)
- [ ] Implement contract invariant testing
- [ ] Add property-based testing for edge cases
- [ ] Create automated DLQ replay integration
- [ ] Add performance regression testing
- [ ] Implement synthetic monitoring in production

---

**Maintained by:** [Your Name]
**Last Review:** 2025-11-02
