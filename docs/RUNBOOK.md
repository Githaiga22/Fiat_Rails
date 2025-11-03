# FiatRails Runbook

**Candidate:** Allan Robinson 
**Version:** 1.0  
**Last Updated:** 2025/11/02

---

## Overview

This runbook covers operational procedures for FiatRails in production. It assumes familiarity with the system architecture (see ADR.md).

**On-Call Contact:** [Your Name/Email]  
**Escalation:** [Next Level]  
**Incident Channel:** #fiatrails-incidents

---

## Table of Contents

1. [SLOs & Monitoring](#slos--monitoring)
2. [Alert Response Procedures](#alert-response-procedures)
3. [Contract Upgrade Rollback](#contract-upgrade-rollback)
4. [HMAC Secret Rotation](#hmac-secret-rotation)
5. [Dead-Letter Queue Processing](#dead-letter-queue-processing)
6. [Degraded Mode Operations](#degraded-mode-operations)
7. [Database Backup & Restore](#database-backup--restore)
8. [Common Issues & Fixes](#common-issues--fixes)

---

## SLOs & Monitoring

### Service Level Objectives

| Metric | Target | Measurement Window | Alert Threshold |
|--------|--------|-------------------|-----------------|
| Availability | 99.9% | 30 days | < 99.5% |
| API p95 Latency | < 500ms | 5 minutes | > 1s |
| RPC p95 Latency | < 2s | 5 minutes | > 3s |
| Mint Success Rate | > 95% | 1 hour | < 90% (for compliant users) |
| RPC Error Rate | < 5% | 5 minutes | > 10% |

### Key Dashboards

- **Production Overview:** http://grafana:3001/d/fiatrails-overview
- **RPC Health:** http://grafana:3001/d/fiatrails-rpc
- **DLQ Monitoring:** http://grafana:3001/d/fiatrails-dlq

### Critical Metrics

```promql
# RPC Error Rate
rate(fiatrails_rpc_errors_total[5m]) / rate(fiatrails_rpc_requests_total[5m])

# DLQ Depth
fiatrails_dlq_depth

# Mint Success Rate
rate(fiatrails_mint_intents_total{status="executed"}[5m]) 
/ 
rate(fiatrails_mint_intents_total[5m])
```

---

## Alert Response Procedures

###  CRITICAL: HighRPCErrorRate

**Alert:** RPC error rate > 10% for 2+ minutes

**Impact:** Mints failing, webhooks not processed

**Diagnosis:**
```bash
# Check RPC connectivity
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Check recent errors
docker logs fiatrails-api | grep -i "rpc error" | tail -20

# Check Prometheus
curl http://localhost:9090/api/v1/query?query=fiatrails_rpc_errors_total
```

**Remediation:**
1. **If RPC provider issue:** Switch to fallback RPC
   ```bash
   export RPC_URL=https://fallback-rpc.example.com
   docker compose restart api
   ```

2. **If rate limiting:** Reduce request rate or upgrade RPC tier

3. **If network issue:** Check firewall/DNS
   ```bash
   ping rpc-provider.com
   traceroute rpc-provider.com
   ```

**Escalation:** If no RPC available, page infrastructure team

---

###  CRITICAL: DLQGrowing

**Alert:** DLQ has > 10 items for 5+ minutes

**Impact:** Webhooks/mints not processing, backlog building

**Diagnosis:**
```bash
# Check DLQ contents
cat /app/dlq/*.json | jq .

# Check API logs for failures
docker logs fiatrails-api | grep -i "dlq" | tail -50

# Common causes:
# - RPC down (see HighRPCErrorRate)
# - Compliance check failing
# - Nonce issues
```

**Remediation:**
1. **If RPC issue:** Fix RPC first (see above)

2. **If compliance issue:** Check UserRegistry
   ```bash
   # Check if UserRegistry contract is accessible
   cast call <USER_REGISTRY_ADDRESS> "isCompliant(address)" <USER_ADDRESS>
   ```

3. **Manual DLQ replay:**
   ```bash
   node scripts/replay-dlq.js --item-id <ID>
   ```

**Prevention:** Auto-retry DLQ items every 10 minutes (cron job)

---

###  WARNING: SlowRPCCalls

**Alert:** p95 RPC latency > 2s for 5+ minutes

**Impact:** Slow user experience, potential timeouts

**Diagnosis:**
```bash
# Check RPC latency
time cast block-number --rpc-url $RPC_URL

# Check for block lag
cast block-number --rpc-url $RPC_URL
# Compare with public block explorer
```

**Remediation:**
1. **If provider slow:** Switch to faster RPC
2. **If chain congested:** Increase timeout, reduce retry frequency
3. **If regional latency:** Use geographically closer RPC

---

###  WARNING: NoSuccessfulMints

**Alert:** Zero successful mints in 10 minutes

**Impact:** Revenue stopped, users blocked

**Diagnosis:**
```bash
# Check if intents are being submitted
curl http://localhost:3000/health

# Check compliance rate
cast call <USER_REGISTRY_ADDRESS> "isCompliant(address)" <TEST_USER>

# Check if contract paused
cast call <ESCROW_ADDRESS> "paused()(bool)"
```

**Remediation:**
1. **If paused:** Unpause (requires ADMIN role)
   ```bash
   cast send <ESCROW_ADDRESS> "unpause()" --private-key $ADMIN_KEY
   ```

2. **If compliance blocking all:** Review compliance settings
   - Check `maxRiskScore` in seed.json
   - Verify attestations are current

3. **If no webhooks:** Check M-PESA integration health

---

## Contract Upgrade Rollback

### Scenario

A bad upgrade was deployed and needs to be rolled back.

### Pre-requisites

- UPGRADER_ROLE on the ComplianceManager
- Previous implementation address (from deploy logs)
- Testnet rollback tested

### Procedure

**1. Identify Previous Implementation**

```bash
# Get proxy admin
cast call <PROXY_ADDRESS> "implementation()(address)"

# Check deploy logs for previous version
cat deploy-history.log | grep "Implementation deployed"
```

**2. Test Rollback on Fork**

```bash
# Start Anvil fork
anvil --fork-url $MAINNET_RPC --fork-block-number <BLOCK_BEFORE_UPGRADE>

# Deploy previous implementation to fork
forge script script/DeployV1.s.sol --rpc-url http://localhost:8545

# Perform upgrade on fork
cast send <PROXY_ADDRESS> "upgradeTo(address)" <PREVIOUS_IMPL> \
  --private-key $UPGRADER_KEY --rpc-url http://localhost:8545

# Test critical functions
cast call <PROXY_ADDRESS> "isCompliant(address)" <TEST_USER>
```

**3. Execute Rollback on Production**

```bash
# Pause system first (optional but recommended)
cast send <COMPLIANCE_MANAGER> "pause()" --private-key $ADMIN_KEY

# Perform rollback
cast send <PROXY_ADDRESS> "upgradeTo(address)" <PREVIOUS_IMPL> \
  --private-key $UPGRADER_KEY \
  --gas-limit 500000

# Verify
cast call <PROXY_ADDRESS> "implementation()(address)"

# Unpause
cast send <COMPLIANCE_MANAGER> "unpause()" --private-key $ADMIN_KEY
```

**4. Post-Rollback Verification**

```bash
# Smoke test critical paths
node scripts/smoke-test.js

# Check events
cast logs --from-block <ROLLBACK_BLOCK> <PROXY_ADDRESS>

# Monitor dashboards for 30 minutes
```

**5. Incident Report**

Document:
- What went wrong in the upgrade
- How it was detected
- Rollback timeline
- Prevention measures

---

## HMAC Secret Rotation

### Scenario

HMAC secret may have been compromised or is due for scheduled rotation.

### Goal

Rotate secret with **zero downtime** (both old and new secrets valid during transition).

### Procedure

**1. Generate New Secret**

```bash
# Generate cryptographically random secret
openssl rand -hex 32 > new-hmac-secret.txt

# Store in secrets manager
aws secretsmanager create-secret \
  --name fiatrails/hmac-secret-v2 \
  --secret-string file://new-hmac-secret.txt
```

**2. Deploy Dual-Verification Mode**

Update API to accept both old and new HMAC:

```javascript
function verifyHMAC(request) {
    const oldSecret = process.env.HMAC_SECRET;
    const newSecret = process.env.HMAC_SECRET_NEW;
    
    const validOld = checkHMAC(request, oldSecret);
    const validNew = checkHMAC(request, newSecret);
    
    return validOld || validNew; // Accept either
}
```

**3. Rolling Deploy**

```bash
# Set both secrets
export HMAC_SECRET=<old-secret>
export HMAC_SECRET_NEW=<new-secret>

# Deploy with zero downtime (blue-green or rolling)
docker compose up -d --scale api=2
docker compose stop api-old

# Monitor error rate (should be unchanged)
```

**4. Notify Client Services**

Email all API consumers:
> HMAC secret rotation in progress. Please update to new secret by [DATE]. Old secret will be revoked in 7 days.

**5. Wait for Transition Period (7 days)**

Monitor:
```bash
# Track which secret is being used
curl http://localhost:9090/api/v1/query?query=fiatrails_hmac_verifications_total
```

**6. Revoke Old Secret**

```bash
# Remove old secret from environment
unset HMAC_SECRET
export HMAC_SECRET=$HMAC_SECRET_NEW
unset HMAC_SECRET_NEW

# Deploy
docker compose restart api

# Monitor for auth failures (should be zero)
```

**7. Update Documentation**

- Update `seed.json` with new `hmacSalt`
- Document rotation date in change log

---

## Dead-Letter Queue Processing

### Scenario

DLQ has items that failed after max retries.

### Diagnosis

**1. Inspect DLQ Item**

```bash
ls /app/dlq/
cat /app/dlq/item-<ID>.json | jq .
```

Example item:
```json
{
  "operation": "executeMint",
  "intentId": "0xabc...",
  "attempts": 5,
  "lastError": "RPC timeout",
  "timestamp": "2025-11-01T12:34:56Z",
  "payload": { ... }
}
```

**2. Determine Failure Reason**

Common reasons:
- RPC was down (temporary) → safe to retry
- Nonce issue (resolved) → safe to retry
- User not compliant (permanent) → mark as failed, notify user
- Contract bug (requires fix) → wait for upgrade

### Manual Replay

**1. If Safe to Retry:**

```bash
node scripts/replay-dlq.js --item-id <ID>
```

**2. If Requires Intervention:**

```bash
# Check current state on-chain
cast call <ESCROW_ADDRESS> "getIntentStatus(bytes32)" <INTENT_ID>

# If already executed on-chain but DLQ thinks it failed:
# → Update DB, remove DLQ item (reconciliation issue)

# If user now non-compliant:
# → Refund intent
cast send <ESCROW_ADDRESS> "refundIntent(bytes32,string)" \
  <INTENT_ID> "User no longer compliant" \
  --private-key $OPERATOR_KEY
```

**3. Bulk Replay (after RPC restoration):**

```bash
# Replay all DLQ items from last 1 hour
node scripts/replay-dlq.js --since "1 hour ago"
```

### Prevention

- Auto-retry DLQ items every 10 minutes (cron)
- Alert if DLQ depth > 10
- Weekly DLQ review meeting

---

## Degraded Mode Operations

### Scenario: RPC Completely Down

**Impact:** Can't submit transactions, can't read blockchain state

**Degraded Mode Actions:**

1. **Accept intents but don't execute:**
   ```bash
   # Set READ_ONLY mode
   export DEGRADED_MODE=true
   docker compose restart api
   
   # API will:
   # - Accept POST /mint-intents (store in DB)
   # - Return 503 for webhooks
   # - Queue for later processing
   ```

2. **Communicate to users:**
   - Status page: "Minting temporarily unavailable"
   - ETA for restoration

3. **When RPC restored:**
   ```bash
   unset DEGRADED_MODE
   docker compose restart api
   
   # Process queued intents
   node scripts/process-backlog.js
   ```

### Scenario: Database Down

**Impact:** Can't check idempotency, can't store DLQ

**Degraded Mode Actions:**

1. **Fallback to in-memory cache (risky):**
   ```bash
   export DB_FALLBACK_MODE=memory
   # WARNING: Idempotency only preserved until restart
   ```

2. **Reject all writes:**
   ```bash
   export READ_ONLY=true
   # All POST requests return 503
   ```

3. **Restore from backup:**
   See [Database Backup & Restore](#database-backup--restore)

---

## Database Backup & Restore

### Backup (Automated Daily)

```bash
# PostgreSQL
pg_dump -U postgres -d fiatrails > backup-$(date +%Y%m%d).sql

# Upload to S3
aws s3 cp backup-*.sql s3://fiatrails-backups/
```

### Restore

```bash
# Download latest backup
aws s3 cp s3://fiatrails-backups/backup-20251101.sql .

# Restore
docker compose stop api
docker compose exec postgres psql -U postgres -d fiatrails < backup-20251101.sql
docker compose start api

# Verify
docker compose exec postgres psql -U postgres -d fiatrails -c "SELECT COUNT(*) FROM idempotency_keys;"
```

---

## Common Issues & Fixes

### Issue: `nonce too low`

**Cause:** Transaction submitted with old nonce

**Fix:**
```javascript
// In API code, always fetch latest nonce
const nonce = await provider.getTransactionCount(signer.address, 'pending');
```

**Temporary workaround:**
```bash
# Manually set nonce
export NONCE_OVERRIDE=<correct-nonce>
```

---

### Issue: "User not compliant" but user just completed KYC

**Cause:** Attestation not yet recorded on-chain

**Fix:**
```bash
# Check UserRegistry
cast call <USER_REGISTRY> "getUser(address)" <USER_ADDRESS>

# If attestation missing, record it
cast send <USER_REGISTRY> "updateUser(address,uint8,bytes32,bool)" \
  <USER> <RISK_SCORE> <ATTESTATION_HASH> true \
  --private-key $COMPLIANCE_OFFICER_KEY
```

---

### Issue: Grafana dashboard shows "No data"

**Cause:** Prometheus not scraping metrics

**Fix:**
```bash
# Check Prometheus targets
curl http://localhost:9090/api/v1/targets | jq .

# Restart Prometheus
docker compose restart prometheus

# Verify metrics endpoint
curl http://localhost:3000/metrics
```

---

### Issue: Docker container won't start

**Cause:** Port already in use, volume mount issue, or bad config

**Fix:**
```bash
# Check logs
docker compose logs api

# Common fixes:
# - Port conflict: change port in docker-compose.yml
# - Volume permission: chown -R $(id -u):$(id -g) ./data
# - Bad env var: check .env file syntax
```

---
