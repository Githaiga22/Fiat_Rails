# Threat Model

**Candidate:** [Your Candidate ID]  
**Date:** [Submission Date]  
**Version:** 1.0

---

## Overview

This document identifies attack surfaces in the FiatRails system and documents mitigations.

**Risk Rating:**
-  **Critical:** Direct loss of funds or total system compromise
-  **High:** Significant degradation or partial fund loss
- 🟠 **Medium:** Service disruption or data corruption
- 🟢 **Low:** Minor inconvenience or information disclosure

---

## 1. Smart Contract Threats

### T-001: Reentrancy Attack 

**Attack Vector:**
Malicious contract calls back into MintEscrow during token transfer, potentially double-minting.

```solidity
// Vulnerable pattern
escrow.executeMint(intentId);
  → transfer tokens to user
    → user's receive() calls executeMint again
```

**Likelihood:** Medium (if external calls before state updates)  
**Impact:** Critical (double-spend)

**Mitigation:**
- Checks-Effects-Interactions pattern
- ReentrancyGuard on public functions
- State updated before external calls

```solidity
// Example mitigation
function executeMint(bytes32 intentId) external nonReentrant {
    MintIntent storage intent = intents[intentId];
    require(intent.status == MintStatus.Pending, "Already executed");
    
    intent.status = MintStatus.Executed; // State change first
    
    _mintCountryToken(intent.user, intent.amount); // Then external call
}
```

**Testing:**
- Unit test with malicious contract that reenters
- Invariant test: "total mints ≤ total deposits"

---

### T-002: Upgrade Bricking 

**Attack Vector:**
Deploying a broken implementation contract that can't be upgraded further, permanently locking funds.

**Likelihood:** Low (if proper testing)  
**Impact:** Critical (funds locked forever)

**Mitigation:**
- `_authorizeUpgrade()` requires UPGRADER role
- Storage layout preserved (use storage gap)
- `_disableInitializers()` in implementation constructor
- Test upgrade path on testnet before production

```solidity
function _authorizeUpgrade(address newImplementation) 
    internal 
    override 
    onlyRole(UPGRADER_ROLE) 
{
    // Additional checks on newImplementation
    require(newImplementation != address(0), "Invalid implementation");
}
```

**Testing:**
- Test upgrade to dummy V2 contract
- Verify storage slots unchanged
- Test that implementation can't be initialized

---

### T-003: Role Escalation 

**Attack Vector:**
Unauthorized user gains ADMIN or UPGRADER role, allowing them to pause system or steal funds via malicious upgrade.

**Likelihood:** Low (if access control correct)  
**Impact:** Critical (full system compromise)

**Mitigation:**
- AccessControl from OpenZeppelin
- Multi-sig for admin operations (in production)
- Time-delay for sensitive operations (optional)
- Events for all role grants

```solidity
function grantRole(bytes32 role, address account) 
    public 
    override 
    onlyRole(getRoleAdmin(role)) 
{
    super.grantRole(role, account);
    emit RoleGranted(role, account, msg.sender); // Audit trail
}
```

**Testing:**
- Unauthorized users can't grant roles
- Only DEFAULT_ADMIN_ROLE can grant ADMIN
- Events emitted for auditing

---

### T-004: Front-Running / MEV 

**Attack Vector:**
Searchers see compliance approval transaction and front-run with mint, or sandwich compliance updates.

**Likelihood:** High (public mempool)  
**Impact:** Medium (user experience degradation, not fund loss)

**Mitigation:**
- Compliance check happens atomically with mint
- Flashbots/private RPC for sensitive transactions (production)
- 🔄 Alternative: Commit-reveal for compliance attestations

**Testing:**
- Simulate front-running in test (fork mode)

---

### T-005: Signature Replay (On-Chain) 

**Attack Vector:**
If permits or signed messages used, replay on different chains or after nonce increment.

**Likelihood:** Medium (if using EIP-712 signatures)  
**Impact:** Medium (duplicate operations)

**Mitigation:**
- Include chainId in signature domain
- Include nonce per user
- Mark signature as used after consumption

**Testing:**
- Test signature can't be replayed
- Test signature invalid on different chainId

---

### T-006: Integer Overflow/Underflow 🟢

**Attack Vector:**
Arithmetic operations overflow, causing incorrect balances.

**Likelihood:** Very Low (Solidity 0.8+ has built-in checks)  
**Impact:** Critical (if it happened)

**Mitigation:**
- Solidity ^0.8.0 (checked arithmetic by default)
- SafeMath not needed for 0.8+

**Testing:**
- Fuzz tests with extreme values

---

## 2. API Threats

### T-101: HMAC Signature Forgery 

**Attack Vector:**
Attacker guesses or brute-forces HMAC secret, forges valid requests to drain funds.

**Likelihood:** Low (if secret strong)  
**Impact:** Critical (unauthorized mints)

**Mitigation:**
- HMAC secret ≥ 256 bits entropy (from seed.json)
- Verify HMAC on all authenticated endpoints
- Constant-time comparison to prevent timing attacks
- Secret never logged or exposed in errors

```javascript
const crypto = require('crypto');

function verifyHMAC(request, secret) {
    const payload = request.timestamp + request.body;
    const expected = crypto.createHmac('sha256', secret).update(payload).digest('hex');
    
    // Constant-time comparison
    return crypto.timingSafeEqual(
        Buffer.from(request.signature, 'hex'),
        Buffer.from(expected, 'hex')
    );
}
```

**Testing:**
- Valid HMAC accepted
- Invalid HMAC rejected (401)
- Timing attack resistance (all failures take same time)

---

### T-102: Replay Attacks (Webhook) 

**Attack Vector:**
Attacker captures M-PESA webhook payload and replays it multiple times to mint repeatedly.

**Likelihood:** Medium (webhook URLs often leak)  
**Impact:** High (double-mints)

**Mitigation:**
- Check timestamp freshness (reject if > 5min old)
- Idempotency via `txRef` (store in DB)
- Verify HMAC includes timestamp

```javascript
function validateTimestamp(timestamp) {
    const now = Date.now() / 1000;
    const age = now - timestamp;
    
    if (age > 300) { // 5 minutes
        throw new Error('Replay: timestamp too old');
    }
    if (age < -60) { // 1 minute in future (clock skew)
        throw new Error('Timestamp in future');
    }
}
```

**Testing:**
- Old timestamp rejected
- Duplicate txRef returns 200 but doesn't mint again

---

### T-103: Idempotency Key Collision 🟠

**Attack Vector:**
Two different operations hash to same idempotency key, causing wrong response returned.

**Likelihood:** Very Low (if crypto hash used)  
**Impact:** Medium (user confusion, not fund loss)

**Mitigation:**
- Use SHA-256 (collision-resistant)
- Include all distinguishing fields in hash
- UUIDs as idempotency keys (client-generated)

**Testing:**
- Different payloads → different keys
- Birthday attack resistance (hash space analysis)

---

### T-104: Nonce Griefing 

**Attack Vector:**
Attacker front-runs your transaction with higher gas, incrementing nonce and causing `nonce too low` errors in your service.

**Likelihood:** Low (requires attacker knowing your address)  
**Impact:** Medium (service degradation, not fund loss)

**Mitigation:**
- Retry with fresh nonce on `nonce too low`
- Nonce management library (e.g., ethers.js manages this)
- Monitor for anomalous nonce gaps

```javascript
async function sendTransaction(tx) {
    const nonce = await provider.getTransactionCount(signer.address, 'pending');
    tx.nonce = nonce;
    
    try {
        return await signer.sendTransaction(tx);
    } catch (err) {
        if (err.code === 'NONCE_EXPIRED') {
            // Retry with fresh nonce
            return await sendTransaction(tx);
        }
        throw err;
    }
}
```

**Testing:**
- Simulate `nonce too low` error
- Verify retry logic

---

### T-105: RPC Endpoint Denial of Service 🟠

**Attack Vector:**
Malicious RPC provider censors transactions or returns false data.

**Likelihood:** Medium (centralized RPC risk)  
**Impact:** High (service unavailable)

**Mitigation:**
- Fallback RPC endpoints
- Health checks on RPC (measure latency, block lag)
- Circuit breaker pattern
- 🔄 Future: Run own node

**Testing:**
- Simulate RPC timeout
- Verify fallback to secondary RPC

---

### T-106: SQL Injection 

**Attack Vector:**
User-controlled input in SQL query allows data exfiltration or corruption.

**Likelihood:** Low (if parameterized queries used)  
**Impact:** High (database compromise)

**Mitigation:**
- Parameterized queries / ORM
- Input validation (whitelists, not blacklists)
- Least privilege DB user

```javascript
// Safe
const result = await db.query(
    'SELECT * FROM intents WHERE intentId = $1',
    [intentId]
);

// Vulnerable
const result = await db.query(
    `SELECT * FROM intents WHERE intentId = '${intentId}'`
);
```

**Testing:**
- Injection payloads (`' OR '1'='1`) rejected

---

## 3. Operational Threats

### T-201: Private Key Leakage 

**Attack Vector:**
Private key for transaction signing committed to Git, leaked in logs, or stolen from server.

**Likelihood:** Medium (common mistake)  
**Impact:** Critical (attacker drains funds)

**Mitigation:**
- Private keys in environment variables only
- `.gitignore` for `.env` files
- Secrets manager (AWS Secrets, Vault) in production
- Audit logs for key access

**Testing:**
- `git log | grep -i "private"` → no results
- Secrets not in Docker image layers

---

### T-202: Docker Image Backdoor 

**Attack Vector:**
Malicious base image or dependency contains backdoor that exfiltrates keys.

**Likelihood:** Low (but high impact)  
**Impact:** Critical (keys stolen)

**Mitigation:**
- Pin base image SHA (not `latest`)
- Scan images with Trivy/Snyk
- Minimal base image (Alpine, Distroless)
- Multi-stage builds (no build tools in final image)

```dockerfile
# Pinned
FROM node:18-alpine@sha256:abc123...

# Vulnerable
FROM node:latest
```

**Testing:**
- Image scan in CI
- No high/critical CVEs

---

### T-203: Chain Reorganization (Reorg) 

**Attack Vector:**
Chain reorgs after you've marked a mint as executed, leading to double-mint.

**Likelihood:** Low (on mainnet with many confirmations)  
**Impact:** High (duplicate mints)

**Mitigation:**
- Wait for N confirmations before finality (N=12 for Ethereum)
- Monitor for reorgs (compare blockhashes)
- Mark intents as `pending_confirmation` until final

**Testing:**
- Simulate reorg in Anvil (fork + rewind)
- Verify no double-execution

---

### T-204: Denial of Service (Rate Limiting) 🟠

**Attack Vector:**
Attacker floods API with requests, exhausting resources.

**Likelihood:** High (public endpoints)  
**Impact:** Medium (service unavailable for legit users)

**Mitigation:**
- Rate limiting by IP (e.g., 100 req/min)
- Authentication required for sensitive endpoints
- CAPTCHA for public endpoints (if needed)
- Auto-scaling/load balancer

**Testing:**
- Exceed rate limit → 429 response
- Legit traffic unaffected

---

## 4. Compliance & Business Logic Threats

### T-301: Compliance Bypass 

**Attack Vector:**
User with high risk score bypasses check and mints tokens.

**Likelihood:** Medium (if logic flawed)  
**Impact:** Critical (regulatory violation)

**Mitigation:**
- Compliance check in `executeMint()`, not just `submitIntent()`
- Atomic check-and-mint (no TOCTOU)
- Events log all compliance decisions

```solidity
function executeMint(bytes32 intentId) external {
    MintIntent storage intent = intents[intentId];
    
    // Check compliance at execution time
    require(userRegistry.isCompliant(intent.user), "User not compliant");
    
    _mint(intent.user, intent.amount);
}
```

**Testing:**
- Non-compliant user can't mint
- Compliance revoked mid-flight → mint fails

---

### T-302: Attestation Forgery 

**Attack Vector:**
User provides fake attestation hash (e.g., hash of random data).

**Likelihood:** Medium (if off-chain verification weak)  
**Impact:** High (non-KYC'd users get access)

**Mitigation:**
- Attestation hash is hash of signed ZK proof or doc
- On-chain: only verify hash existence (not content)
- Off-chain: compliance officer verifies original doc
- 🔄 Future: ZK proofs for privacy-preserving KYC

**Testing:**
- Bogus hash doesn't grant compliance (must be set by admin)

---

## 5. Dependency Threats

### T-401: Vulnerable Dependencies 🟠

**Attack Vector:**
NPM/cargo package with known vulnerability (e.g., prototype pollution).

**Likelihood:** Medium (new CVEs daily)  
**Impact:** Varies (RCE in worst case)

**Mitigation:**
- `npm audit` / `cargo audit` in CI
- Dependabot for auto-updates
- Pin exact versions in `package-lock.json`

**Testing:**
- CI fails on high/critical vulnerabilities

---

## Attack Tree Diagram

```
                   [Steal Funds]
                        |
       +----------------+----------------+
       |                                 |
  [On-Chain]                        [Off-Chain]
       |                                 |
   +---+---+                         +---+---+
   |       |                         |       |
Reentrancy Upgrade                HMAC     Key
           Brick                  Forge    Leak
```

[Optionally: Include visual diagram using Excalidraw or similar]

---

## Residual Risks

**Accepted Risks (for this trial):**
- Single-key signature (no multi-sig)
- SQLite instead of HA database
- No formal audit

**Production TODO:**
- Multi-sig for admin operations
- Hardware wallet for private keys
- Third-party audit (Trail of Bits, OpenZeppelin)
- Bug bounty program

---

## Summary

| Threat ID | Category | Severity | Mitigation Status |
|-----------|----------|----------|-------------------|
| T-001 | Reentrancy |  | Mitigated |
| T-002 | Upgrade Brick |  | Mitigated |
| T-003 | Role Escalation |  | Mitigated |
| T-101 | HMAC Forgery |  | Mitigated |
| T-102 | Replay Attack |  | Mitigated |
| T-201 | Key Leakage |  | Mitigated |
| T-203 | Chain Reorg |  | Partially (needs confirmation depth) |
| T-301 | Compliance Bypass |  | Mitigated |

---

**Signed:** [Your Name]  
**Date:** [Date]

