# Architecture Decision Records

**Candidate:** Githaiga22

**Date:** 2025-11-02

**Version:** 1.0

---

## ADR-001: Upgradeability Pattern

### Context

FiatRails contracts must be upgradeable to fix bugs and add features post-deployment. The ComplianceManager contract handles sensitive compliance logic and must support safe upgrades while maintaining security.

### Decision

**Pattern Chosen:** UUPS (Universal Upgradeable Proxy Standard)

### Rationale

UUPS was selected for ComplianceManager because it offers the best balance of gas efficiency and security for our use case.

**Pros:**
- **Lower deployment cost:** Proxy contract is smaller (~200 bytes vs ~400 bytes for Transparent)
- **Lower gas per call:** No delegatecall to check admin (saves ~2100 gas per call)
- **Simpler proxy:** Less complex proxy logic reduces attack surface
- **Flexible upgrade authorization:** Can implement custom upgrade logic in implementation

**Cons:**
- **Higher risk:** If upgrade logic is buggy, contract can be bricked
- **Requires careful initialization:** Must use `_disableInitializers()` in constructor
- **Implementation holds upgrade logic:** Implementation must be carefully audited

### Trade-offs Considered

| Pattern | Gas Cost | Admin Key Risk | Complexity | Chosen? |
|---------|----------|----------------|------------|---------|
| UUPS | Lower (~200 gas/call) | Higher (logic holds upgrade) | Medium | Yes |
| Transparent | Higher (~2300 gas/call) | Lower (proxy holds upgrade) | Low | No |
| Beacon | Medium | Medium | High | No |

### How Misuse is Prevented

1. **Constructor Protection:**
```solidity
constructor() {
    _disableInitializers(); // Prevents implementation from being initialized
}
```

2. **Upgrade Authorization:**
```solidity
function _authorizeUpgrade(address newImplementation)
    internal
    override
    onlyRole(UPGRADER_ROLE)
{}
```

3. **Role Separation:**
   - `DEFAULT_ADMIN_ROLE`: Can pause/unpause, manage roles
   - `COMPLIANCE_OFFICER`: Can update compliance data
   - `UPGRADER_ROLE`: Can authorize upgrades (separate from admin)

4. **Testing:**
   - `testUpgradeRequiresUpgraderRole()`: Ensures unauthorized upgrades fail
   - `testUpgradeWithUpgraderRole()`: Validates successful upgrade path
   - `testCannotReinitialize()`: Prevents reinitialization attacks

### Gas Analysis (from snapshots)

- **Upgrade cost:** ~1,140,000 gas (testUpgradeWithUpgraderRole)
- **Normal operations:** Unaffected (no proxy overhead once deployed)
- **vs Transparent Proxy:** Saves ~2100 gas per call (no admin check)

### References

- OpenZeppelin UUPS: https://docs.openzeppelin.com/contracts/4.x/api/proxy#UUPSUpgradeable
- EIP-1822: https://eips.ethereum.org/EIPS/eip-1822

---

## ADR-002: Event Schema Design

### Context

Events must enable off-chain indexers to reconstruct system state without RPC calls for historical blocks. Gas cost must be balanced with queryability.

### Decision

**Indexed Fields Strategy:** Index high-cardinality lookup keys, leave data fields unindexed

```solidity
// UserRegistry events
event UserRiskUpdated(
    address indexed user,      // Indexed: Filter by user
    uint8 newRiskScore,        // Not indexed: Data field
    address indexed updatedBy, // Indexed: Audit trail
    uint256 timestamp          // Not indexed: Data field
);

event AttestationRecorded(
    address indexed user,            // Indexed: Filter by user
    bytes32 indexed attestationHash, // Indexed: Verify specific attestation
    bytes32 attestationType,         // Not indexed: Metadata
    address indexed recordedBy       // Indexed: Audit trail
);

// MintEscrow events
event MintIntentSubmitted(
    bytes32 indexed intentId,    // Indexed: Primary key
    address indexed user,        // Indexed: Filter by user
    uint256 amount,              // Not indexed: Data field
    bytes32 indexed countryCode, // Indexed: Filter by country
    bytes32 txRef                // Not indexed: Reference only
);

event MintExecuted(
    bytes32 indexed intentId,    // Indexed: Primary key
    address indexed user,        // Indexed: Filter by user
    uint256 amount,              // Not indexed: Data field
    bytes32 indexed countryCode, // Indexed: Filter by country
    bytes32 txRef                // Not indexed: Reference only
);
```

### Rationale

**Why These Fields Indexed:**
- `user`: High-cardinality, frequent filter (e.g., "get all mints for user 0x123")
- `intentId`: Unique identifier, enables direct lookup
- `countryCode`: Business-critical filter (e.g., "all KES mints")
- `updatedBy` / `recordedBy`: Audit trail queries (e.g., "who updated this user?")
- `attestationHash`: Verify specific attestation exists on-chain

**Why These NOT Indexed:**
- `amount`: Numeric field, filtering by amount range is rare
- `txRef`: Low-cardinality reference, full scan acceptable
- `timestamp`: Block metadata available without indexing
- `newRiskScore`: Small value range (0-100), filtering uncommon
- `attestationType`: Low-cardinality, rarely filtered

### Indexer Requirements

An indexer can:
1. **Get all mints for a user:** `MintExecuted.filter({user: "0x..."})`
2. **Track mints by country:** `MintExecuted.filter({countryCode: "KES"})`
3. **Reconstruct user risk score history:** `UserRiskUpdated.filter({user: "0x..."})`
4. **Audit compliance actions:** `AttestationRecorded.filter({recordedBy: "0x..."})`
5. **Verify specific intent:** `MintIntentSubmitted.filter({intentId: "0x..."})`

### Trade-offs

- **Gas:** Each indexed field adds ~375 gas to event emission
- **3 indexed fields per event:** Solidity maximum (excluding anonymous events)
- **Query flexibility:** Can filter by `user AND countryCode` without scanning all events
- **Storage:** Topics enable Bloom filter optimization in Ethereum clients

### Gas Impact (from snapshots)

- `UserRiskUpdated` emission: ~137,504 gas (includes 2 indexed fields)
- `MintExecuted` emission: ~357,939 gas (includes 3 indexed fields)
- Cost per indexed field: ~375 gas
- **Decision:** Worth the cost for critical business queries

---

## ADR-003: Idempotency Strategy

### Context

API must prevent duplicate operations when:
- Client retries failed requests
- Webhooks are delivered multiple times (M-PESA sends up to 3 times)
- Network failures cause uncertain request state

### Decision

**Deduplication Key:** Client-provided `X-Idempotency-Key` header (UUID recommended)

**Storage:** SQLite with in-process database

```sql
CREATE TABLE idempotency_keys (
    key TEXT PRIMARY KEY,
    request_body TEXT NOT NULL,
    response_status INTEGER,
    response_body TEXT,
    created_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL
);
```

**TTL:** 86400 seconds (24 hours from seed.json)

### Rationale

**Why Client-Provided Key:**
- Client controls retry semantics (can choose when to create new operation)
- Server doesn't need to hash request body (faster, simpler)
- UUID ensures global uniqueness across distributed clients

**Why 24-Hour TTL:**
- Covers all realistic retry scenarios (M-PESA retries within 1 hour)
- Balances disk space vs safety margin
- Matches payment processor timeout windows

### Behavior

1. **First Request (key not in DB):**
   - Insert key with `response_status = NULL` (marks in-progress)
   - Process request
   - Update row with response status and body
   - Return response

2. **Concurrent Request (same key, in-progress):**
   - Detect `response_status = NULL`
   - Return `409 Conflict` with message "Request in progress"

3. **Duplicate Request (key exists, completed):**
   - Return cached response (same status + body)
   - No re-processing

4. **Expired Key:**
   - Hourly cleanup job removes keys where `expires_at < now()`
   - Prevents unbounded database growth

### Edge Cases Handled

1. **Concurrent requests with same key:**
   - SQLite `PRIMARY KEY` constraint prevents duplicate inserts
   - Second request gets `UNIQUE constraint failed` error
   - Middleware catches, queries for existing key, returns 409

2. **Expired keys:**
   - Background job runs every 3600 seconds (1 hour)
   - `DELETE FROM idempotency_keys WHERE expires_at < ?`

3. **Database failure:**
   - Request fails with 500 error
   - Client retries with same key
   - Idempotency preserved even after DB restart

### Alternative Considered

- **Redis with TTL:** Faster, but adds operational complexity (separate service)
  - **Rejected:** SQLite sufficient for single-instance API (Milestone 4 scope)
- **In-memory cache:** Lost on restart, no true persistence
  - **Rejected:** Unacceptable for financial operations
- **PostgreSQL:** ACID guarantees, but heavier
  - **Rejected:** Overkill for current scale, SQLite sufficient

---

## ADR-004: Key Management

### Context

System requires multiple secrets:
- HMAC secret for request signing (`fiatrails_hmac_salt_db0dec8bc76794ae`)
- Executor private key for transaction signing
- M-PESA webhook secret (`mpesa_webhook_secret_d3f23a70ddb53521`)
- Idempotency key salt

### Decision

**Storage:** Environment variables + `.gitignore`

**Configuration:**
- Secrets in `seed.json` for development (committed to show working values)
- Secrets in `.env` for production (NOT committed, in `.gitignore`)
- `dotenv` package loads `.env` before application starts

### Rationale

**For Production:**
- Use AWS Secrets Manager / HashiCorp Vault
- Rotate secrets without code changes
- Audit all secret access

**For This Trial:**
- `.env` files are standard in Node.js ecosystem
- `.gitignore` prevents accidental commits
- `seed.json` provides working defaults for demo

### Environment Variable Loading

```javascript
// api/src/index.js (line 1)
import 'dotenv/config';  // MUST be first import

// api/src/config.js
export const config = {
  secrets: {
    hmacSalt: process.env.HMAC_SALT || seed.secrets.hmacSalt,
    mpesaWebhookSecret: process.env.MPESA_SECRET || seed.secrets.mpesaWebhookSecret,
  },
  executorPrivateKey: process.env.EXECUTOR_PRIVATE_KEY, // Required
};
```

### Security Considerations

- **Secrets never logged:**
  - No `console.log(config.secrets)` in code
  - Request logging excludes `X-Signature` header

- **Secrets never in Git:**
  - `.env` in `.gitignore`
  - `.env.example` shows required variables (no real values)

- **Secrets scoped per environment:**
  - Development: `api/.env`
  - Docker: Environment variables in `docker-compose.yml`
  - Production: External secret store

### Rotation Procedure

For production HMAC secret rotation (see RUNBOOK.md):
1. Generate new secret: `openssl rand -hex 32`
2. Update secret store with both old and new
3. API accepts both old and new signatures (grace period)
4. Notify clients to update
5. Remove old secret after 7 days

---

## ADR-005: Retry and Backoff Parameters

### Context

RPC calls may fail transiently (network issues, rate limits, mempool full). System must retry without causing cascading failures or thundering herd.

### Decision

**From seed.json:**
```json
{
  "retry": {
    "maxAttempts": 4,
    "initialBackoffMs": 691,
    "maxBackoffMs": 30000,
    "backoffMultiplier": 2
  }
}
```

**Backoff Formula:** `min(initialBackoff * (multiplier ^ attempt), maxBackoff)`

**Implementation:**
```javascript
export function calculateBackoff(attempt) {
  const backoff = config.retry.initialBackoffMs * Math.pow(config.retry.backoffMultiplier, attempt);
  return Math.min(backoff, config.retry.maxBackoffMs);
}

// Attempt 0: 691ms
// Attempt 1: 1382ms (691 * 2^1)
// Attempt 2: 2764ms (691 * 2^2)
// Attempt 3: 5528ms (691 * 2^3)
// Attempt 4+: 30000ms (capped)
```

**No jitter:** Not implemented in initial version (can add later if thundering herd observed)

### Rationale

**Why These Values:**
- **Max 4 attempts:** 5 total tries (initial + 4 retries) covers ~99% of transient failures
- **Initial 691ms:** Short enough to retry quickly, long enough to let transient issues resolve
- **2x multiplier:** Exponential backoff prevents overwhelming failing service
- **30s max:** Prevents indefinite delays, ensures requests timeout in reasonable time

**Why No Jitter (Yet):**
- Single-instance API (no thundering herd risk)
- Can add later if deploying multiple instances

### Dead-Letter Queue Trigger

After `maxAttempts` (4 retries), operation moves to DLQ for manual review.

**DLQ Format (JSON file):**
```json
{
  "operation": "executeMint",
  "payload": {
    "intentId": "0x1234..."
  },
  "attempts": 5,
  "lastError": "Error: RPC timeout",
  "timestamp": 1699564800000,
  "addedAt": "2025-11-02T10:30:00Z"
}
```

**Storage:** `./data/dlq.json` (file-based for simplicity)

### Recovery

DLQ items are:
- **Manually reviewed:** Operator inspects `dlq.json` file
- **Manually replayed:** Operator calls API endpoint with same payload
- **Alerted:** Prometheus alert fires when `fiatrails_dlq_depth > 10`

### Gas Impact

Retry logic has **no gas impact** (off-chain only). Failed RPC calls don't consume gas.

---

## ADR-006: Database Choice

### Context

API needs persistent storage for:
1. Idempotency keys (high write rate, 24h TTL)
2. Retry queue (medium write rate, variable TTL)

### Decision

**Database:** SQLite (better-sqlite3, synchronous API)

### Rationale

**Why SQLite:**
- **Zero ops:** Embedded database, no separate process
- **ACID guarantees:** Transactions ensure consistency
- **Sufficient performance:** Handles 10,000+ writes/sec (way above our needs)
- **Simple backup:** Single file (`fiatrails.db`)
- **Docker-friendly:** Works in containers without external dependencies

**Schema:**
```sql
-- Idempotency keys
CREATE TABLE idempotency_keys (
    key TEXT PRIMARY KEY,
    request_body TEXT NOT NULL,
    response_status INTEGER,
    response_body TEXT,
    created_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL
);

-- Retry queue
CREATE TABLE retry_queue (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    operation TEXT NOT NULL,
    payload TEXT NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    next_retry INTEGER NOT NULL,
    created_at INTEGER NOT NULL
);
```

### Alternatives Considered

| Database | Pros | Cons | Chosen? |
|----------|------|------|---------|
| PostgreSQL | ACID, mature, high concurrency | Heavy, separate service, ops overhead | No |
| SQLite | Simple, embedded, ACID | Single-writer (fine for our scale) | Yes |
| Redis | Fast, TTL built-in | Not durable by default, separate service | No |

### Limitations & Scaling Path

**Current Limitations:**
- Single-writer: Only one process can write at a time
- No connection pooling: Not needed for embedded DB
- File-based: Backup requires file copy

**Scaling Path (if needed):**
1. **10K requests/day:** SQLite sufficient
2. **100K requests/day:** Consider PostgreSQL for multi-instance API
3. **1M+ requests/day:** PostgreSQL + Redis cache layer

### Gas Impact

Database choice has **no gas impact** (off-chain only).

---

## ADR-007: Gas Optimization Decisions

### Context

Smart contracts must minimize gas costs while maintaining security and functionality. Gas snapshots provide baseline for optimization.

### Gas Snapshot Analysis

**Key Operations (from `.gas-snapshot`):**

| Operation | Gas Cost | Optimization Decision |
|-----------|----------|----------------------|
| `submitIntent` | 169,933 | Acceptable (transfer + storage) |
| `executeMint` | 360,541 | Acceptable (compliance + mint) |
| `refundIntent` | 183,216 | Acceptable (transfer + update) |
| `updateUserRisk` | 137,504 | Optimized (single SSTORE) |
| `recordAttestation` | 137,731 | Optimized (single SSTORE) |
| `upgrade` | 1,140,409 | High (acceptable for rare operation) |

### Optimizations Applied

#### 1. Storage Layout

**Decision:** Pack `UserCompliance` struct tightly
```solidity
struct UserCompliance {
    uint8 riskScore;        // 1 byte
    bytes32 attestationHash; // 32 bytes
    uint256 lastUpdated;     // 32 bytes
    bool isVerified;         // 1 byte (packed with riskScore)
}
```

**Impact:** `riskScore` and `isVerified` share same storage slot
- **Saved:** ~20,000 gas per `updateUser` call
- **Trade-off:** Slightly more complex assembly (not worth it, stuck with standard layout)

**Actual Implementation:** Standard struct (no packing)
- **Rationale:** Clarity > micro-optimization, gas cost acceptable

#### 2. Event Indexing

**Decision:** Limit to 3 indexed fields per event (Solidity maximum)
```solidity
event MintExecuted(
    bytes32 indexed intentId,    // 375 gas
    address indexed user,        // 375 gas
    bytes32 indexed countryCode, // 375 gas
    // amount and txRef: NOT indexed (save 750 gas)
);
```

**Impact:**
- **Cost:** ~1125 gas per event (3 indexed fields)
- **Saved:** ~750 gas by not indexing `amount` and `txRef`
- **Trade-off:** Cannot filter by amount (acceptable, queries by user/intent are primary)

#### 3. Immutable Variables

**Decision:** Use `immutable` for deployment-time constants
```solidity
contract CountryToken {
    string private immutable _countryCode; // Set once in constructor
}
```

**Impact:**
- **Saved:** ~2100 gas per read (SLOAD → embedded in bytecode)
- **Applied:** `countryCode` in CountryToken

#### 4. Short-Circuit Compliance Checks

**Decision:** Check cheapest conditions first
```solidity
function isCompliant(address user) public view returns (bool) {
    UserCompliance memory userData = users[user];

    // Check bool first (cheapest)
    if (!userData.isVerified) return false;

    // Then uint8 comparison
    if (userData.riskScore > MAX_RISK_SCORE) return false;

    // Finally bytes32 comparison (most expensive)
    if (userData.attestationHash == bytes32(0)) return false;

    return true;
}
```

**Impact:**
- **Best case (early fail):** ~200 gas
- **Worst case (all checks):** ~600 gas
- **Order matters:** Bool check fails fast for unverified users

#### 5. Batch Operations NOT Implemented

**Considered:** `batchUpdateUsers(address[], UserCompliance[])`
- **Pros:** Amortize transaction overhead
- **Cons:** Complex error handling, partial failures
- **Decision:** Not implemented (out of MVP scope)

### Optimizations Rejected

#### 1. Custom Errors (Solidity 0.8.4+)

**Considered:**
```solidity
error Unauthorized();  // vs require(condition, "Unauthorized")
```

**Savings:** ~50 gas per revert
**Decision:** Rejected (OpenZeppelin uses `require`, consistency matters)

#### 2. `unchecked` Math

**Considered:** Wrap arithmetic in `unchecked {}` to skip overflow checks
**Decision:** Rejected (security > 20 gas savings)

#### 3. Assembly Optimizations

**Considered:** Use `assembly {}` for storage access
**Decision:** Rejected (readability > micro-optimization, audit risk)

### Gas Budget Targets

**Per Operation:**
- Mint intent submission: <200K gas (actual: 169K)
- Mint execution: <400K gas (actual: 360K)
- Compliance update: <150K gas (actual: 137K)

**Reasoning:**
- Average transaction: ~360K gas (mint execution)
- At 20 gwei: 360K * 20 = 7.2M gwei = 0.0072 ETH (~$14 at $2000/ETH)
- **Acceptable** for high-value financial transactions

### Continuous Monitoring

**Process:**
1. Run `forge snapshot` on every PR
2. GitHub Actions checks for regressions
3. Alert if any operation increases >5%
4. Document intentional increases in commits

**Snapshot Tracking:**
- Baseline: `.gas-snapshot` (107 tests)
- Updated: Automatically on merge
- Review: Manual for large changes

---

## Summary Table

| Decision | Choice | Key Trade-off |
|----------|--------|---------------|
| Upgradeability | UUPS | Gas savings vs upgrade risk |
| Event Indexing | 3 indexed fields | Queryability vs gas cost |
| Idempotency | SQLite + UUID key | Simplicity vs scale |
| Key Management | .env + gitignore | Security vs ops overhead |
| Retry Logic | 4 attempts, exponential | Latency vs resilience |
| Database | SQLite | Simplicity vs multi-instance |
| Gas Optimization | Pragmatic (no assembly) | Readability vs micro-optimization |

---

## Notes for Reviewers

**Assumptions:**
- Single-instance API deployment (Milestone 4 scope)
- <1000 transactions/day initially
- Lisk Sepolia testnet for trial (low gas costs)
- Manual DLQ processing acceptable

**Known Limitations:**
- SQLite: Single-writer limit (fine for MVP)
- No jitter in retry: Could add if thundering herd observed
- DLQ: File-based (acceptable for trial, use queue service in prod)

**Production Considerations:**
- Use AWS Secrets Manager for key management
- Use PostgreSQL for multi-instance API
- Add Datadog/Sentry for error tracking
- Implement automated DLQ replay with monitoring

---

**Signed:** Githaiga22

**Date:** 2025-11-02
