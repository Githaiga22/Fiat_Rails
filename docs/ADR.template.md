# Architecture Decision Records

**Candidate:** Allan Robinson

**Date:** 2025/11/02

**Version:** 1.0

---

## ADR-001: Upgradeability Pattern

### Context

FiatRails contracts must be upgradeable to fix bugs and add features post-deployment. Several patterns exist: UUPS, Transparent Proxy, Beacon, or Diamond.

### Decision

**Pattern Chosen:** [UUPS / Transparent / Other]

### Rationale

[Explain your choice]

**Pros:**
- 
- 
- 

**Cons:**
- 
- 

### Trade-offs Considered

| Pattern | Gas Cost | Admin Key Risk | Complexity | Chosen? |
|---------|----------|----------------|------------|---------|
| UUPS | Lower | Higher (logic holds upgrade) | Medium | ? |
| Transparent | Higher | Lower (proxy holds upgrade) | Low | ? |
| Beacon | Medium | Medium | High | ? |

### How Misuse is Prevented

[How do you prevent bricking the contract? e.g., `_disableInitializers()`, `onlyProxy` modifier, storage gap]

```solidity
// Example code showing your protection mechanism
```

### References

- OpenZeppelin UUPS: https://docs.openzeppelin.com/contracts/4.x/api/proxy#UUPSUpgradeable
- [Any other resources you consulted]

---

## ADR-002: Event Schema Design

### Context

Events must enable off-chain indexers to reconstruct system state without RPC calls for historical blocks.

### Decision

**Indexed Fields Strategy:** [Describe which fields are indexed and why]

```solidity
event MintExecuted(
    bytes32 indexed intentId,
    address indexed user,
    uint256 amount,            // Not indexed - why?
    bytes32 indexed countryCode,
    bytes32 txRef              // Not indexed - why?
);
```

### Rationale

**Why These Fields Indexed:**
- `intentId`: [Reason]
- `user`: [Reason]
- `countryCode`: [Reason]

**Why These NOT Indexed:**
- `amount`: [Reason]
- `txRef`: [Reason]

### Indexer Requirements

An indexer should be able to:
1. [Capability 1, e.g., "Get all mints for a user"]
2. [Capability 2, e.g., "Track mints by country"]
3. [Capability 3, e.g., "Reconstruct user risk score history"]

### Trade-offs

- **Gas:** Each indexed field adds ~375 gas
- **Query flexibility:** More indexed fields = more query options
- **Storage:** Topic filters are cheap, but more events = more logs

---

## ADR-003: Idempotency Strategy

### Context

API must prevent duplicate operations when:
- Client retries failed requests
- Webhooks are delivered multiple times
- RPC nonce issues cause transaction resubmission

### Decision

**Deduplication Key:** [Format, e.g., "SHA256(user + txRef + amount)"]

**Storage:** [Database choice and schema]

```sql
-- Example schema
CREATE TABLE idempotency_keys (
    key VARCHAR(128) PRIMARY KEY,
    response_status INT,
    response_body TEXT,
    created_at TIMESTAMP,
    expires_at TIMESTAMP
);
```

**TTL:** [How long keys are retained, from seed.json]

### Rationale

**Why This Key Format:**
- 

**Why This TTL:**
- 

### Edge Cases Handled

1. **Concurrent requests with same key:** [How handled? Row lock? Compare-and-swap?]
2. **Expired keys:** [Cleanup strategy? Background job?]
3. **Database failure:** [Fallback behavior?]

### Alternative Considered

- Redis with TTL: [Why rejected or chosen?]
- In-memory cache: [Why rejected?]

---

## ADR-004: Key Management

### Context

System requires multiple secrets:
- HMAC secret for request signing
- RPC private key for transaction signing
- M-PESA webhook secret

### Decision

**Storage:** [Environment variables / HashiCorp Vault / AWS Secrets Manager / other]

**Rotation Strategy:** [How secrets are rotated without downtime]

### Rationale

**For Production:**
- 

**For This Trial:**
- 

### Rotation Procedure (from RUNBOOK)

```bash
# Example rotation command
./scripts/rotate-secret.sh hmac
```

1. [Step 1]
2. [Step 2]
3. [Verification]

### Security Considerations

- Secrets never logged: [How ensured?]
- Secrets never in Git: [How ensured?]
- Secrets scoped per environment: [How managed?]

---

## ADR-005: Retry and Backoff Parameters

### Context

RPC calls may fail transiently (network issues, rate limits, mempool full). System must retry without causing cascading failures.

### Decision

**From seed.json:**
```json
{
  "retry": {
    "maxAttempts": <your value>,
    "initialBackoffMs": <your value>,
    "maxBackoffMs": <your value>,
    "backoffMultiplier": <your value>
  }
}
```

**Backoff Formula:** `min(initialBackoff * (multiplier ^ attempt), maxBackoff) + jitter`

**Jitter:** [How much randomness added to prevent thundering herd?]

### Rationale

**Why These Values:**
- Max attempts: [Reasoning]
- Initial backoff: [Reasoning]
- Multiplier: [Reasoning]

### Dead-Letter Queue Trigger

After `maxAttempts`, operation goes to DLQ for manual review.

**DLQ Format:**
```json
{
  "operation": "executeMint",
  "intentId": "0x...",
  "attempts": 5,
  "lastError": "...",
  "timestamp": "..."
}
```

### Recovery

DLQ items are:
- [Automatically retried after X time?]
- [Manually reviewed and replayed?]
- [Alerted to on-call?]

---

## ADR-006: Database Choice

### Context

API needs persistent storage for idempotency keys and DLQ.

### Decision

**Database:** [PostgreSQL / SQLite / MongoDB / other]

### Rationale

**Why This Database:**
- 
- 

**Schema:**
```sql
-- Tables here
```

### Alternatives Considered

| Database | Pros | Cons | Chosen? |
|----------|------|------|---------|
| PostgreSQL | ACID, mature | Heavier | ? |
| SQLite | Simple, embedded | Single-writer limit | ? |
| Redis | Fast, TTL built-in | Not durable by default | ? |

---

## Summary Table

| Decision | Choice | Key Trade-off |
|----------|--------|---------------|
| Upgradeability | [Pattern] | [Gas vs security] |
| Event Indexing | [Strategy] | [Gas vs queryability] |
| Idempotency | [Key format + storage] | [Complexity vs reliability] |
| Key Management | [Storage method] | [Security vs ops overhead] |
| Retry Logic | [Backoff params] | [Latency vs resilience] |
| Database | [DB choice] | [Simplicity vs scale] |

---

## Notes for Reviewers

[Any additional context, assumptions, or known limitations]

---

**Signed:** Allan Robinson
**Date:** 2025/11/02

