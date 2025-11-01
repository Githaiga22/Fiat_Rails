# FiatRails Production Trial

**Duration:** 8–12 hours over 1–2 days  
**Role:** Senior Protocol Engineer  
**Goal:** Build a minimal, production-shaped slice of FiatRails to demonstrate readiness for production deployment

---

## 📋 Overview

You will build a complete system that handles fiat-to-crypto minting with compliance checks:

- **On-chain (EVM):** Upgradeable smart contracts with role-gating, pausability, and structured events
- **Off-chain (API):** Resilient API service with idempotency, HMAC verification, and retry logic
- **Operations:** Docker-based deployment, observability (Prometheus/Grafana), and runbooks

This trial is designed to evaluate your ability to ship production-ready code under realistic constraints.

---

## 🎯 What You Must Build

### 1. On-Chain Components (Solidity + Foundry)

#### Contracts

**ComplianceManager** (Upgradeable)
- ✅ UUPS upgradeability pattern (or justify alternative in ADR)
- ✅ Role-based access control (ADMIN, COMPLIANCE_OFFICER, UPGRADER)
- ✅ Pausable mechanism for emergency stops
- ✅ Events indexed appropriately for off-chain indexing

**UserRegistry**
- ✅ Store risk score (0-100) per user
- ✅ Store attestation hash (off-chain doc/ZK proof reference)
- ✅ Query interface for compliance checks
- ✅ Access control for writes

**MintEscrow**
- ✅ Accept USD stablecoin deposit intents
- ✅ Check UserRegistry compliance before minting
- ✅ Mint country token (1:1 ratio) only if compliant
- ✅ Prevent double-execution (idempotency)
- ✅ Handle refunds for non-compliant users

**Country Token** (ERC20)
- ✅ Deploy ERC20 token using `seed.json` countryCode as symbol
- ✅ Grant MintEscrow contract minter role
- ✅ 18 decimals to match USD stablecoin

**USD Stablecoin Mock** (ERC20)
- ✅ Deploy mock ERC20 for testing (or use existing on testnet)
- ✅ Pre-mint tokens for test users
- ✅ 18 decimals

#### Events (all must be indexed correctly)

```solidity
event UserRiskUpdated(address indexed user, uint8 newRiskScore, address indexed updatedBy, uint256 timestamp);
event AttestationRecorded(address indexed user, bytes32 indexed attestationHash, bytes32 attestationType, address indexed recordedBy);
event MintIntentSubmitted(bytes32 indexed intentId, address indexed user, uint256 amount, bytes32 indexed countryCode, bytes32 txRef);
event MintExecuted(bytes32 indexed intentId, address indexed user, uint256 amount, bytes32 indexed countryCode, bytes32 txRef);
```

#### Testing Requirements

- ✅ Unit tests for all contract functions
- ✅ Fuzz tests for input validation
- ✅ Invariant tests (e.g., "sum of mints ≤ sum of deposits")
- ✅ Integration tests (multi-contract flows)
- ✅ Gas snapshots (`forge snapshot`)
- ✅ Test coverage > 80%

### 2. Off-Chain API Service

#### Endpoints

**POST /mint-intents**
- ✅ Idempotent (same `X-Idempotency-Key` → same outcome)
- ✅ Request signature verification (HMAC)
- ✅ Submit on-chain mint intent
- ✅ Return intent ID

**POST /callbacks/mpesa** (simulated webhook)
- ✅ Verify HMAC signature (`X-Mpesa-Signature`)
- ✅ Check timestamp freshness (reject replays)
- ✅ Idempotent execution (use txRef as dedup key)
- ✅ Call `escrow.executeMint(intentId)`
- ✅ Retry with exponential backoff on RPC failures
- ✅ Dead-letter queue (DLQ) for exhausted retries

**GET /health**
- ✅ Report service status, RPC connectivity, queue depth

**GET /metrics**
- ✅ Prometheus-compatible metrics endpoint

#### Resilience Requirements

- ✅ **Idempotency:** Dedup keys stored in DB (PostgreSQL/SQLite)
- ✅ **Retry logic:** Exponential backoff (configurable in `seed.json`)
- ✅ **DLQ:** Persist failed operations (file/SQLite acceptable)
- ✅ **RPC failures:** Graceful degradation, don't crash
- ✅ **Nonce management:** Handle `nonce too low` errors

### 3. Operations & Observability

#### Docker Deployment

- ✅ `docker compose up` starts entire system
- ✅ All services containerized (API, Anvil, Postgres, Redis, Prometheus, Grafana)
- ✅ Proper health checks and service dependencies
- ✅ Environment variables for configuration

#### Prometheus Metrics (minimum required)

```
# RPC operations
fiatrails_rpc_requests_total{method, status}
fiatrails_rpc_duration_seconds{method, quantile}
fiatrails_rpc_errors_total{method, error_type}

# Business metrics
fiatrails_mint_intents_total{status}
fiatrails_callbacks_total{source, status}

# Queue metrics
fiatrails_dlq_depth
fiatrails_retry_attempts_total{operation}

# Compliance
fiatrails_compliance_checks_total{result}
```

#### Grafana Dashboard

- ✅ RPC error rate (5m window)
- ✅ p95 latency for RPC and API
- ✅ DLQ depth
- ✅ Successful mint rate
- ✅ Visual alerts for thresholds

#### CI/CD (GitHub Actions)

- ✅ Run Foundry tests
- ✅ Run linter (Solidity + API code)
- ✅ Generate gas report
- ✅ Build Docker images
- ✅ All checks must pass

---

## 📚 Documentation Deliverables

### 1. ADR.md (Architecture Decision Records)

Document key trade-offs:

- Why UUPS vs Transparent proxy (or alternative)?
- Event schema design (which fields indexed, why?)
- Idempotency strategy (storage, TTL, key format)
- Key management approach (HMAC secrets, private keys)
- Database choice and schema
- Retry/backoff parameters

### 2. THREAT_MODEL.md

Identify attack surfaces and mitigations:

- **On-chain:** Reentrancy, replay attacks, role escalation, upgrade bricking
- **Off-chain:** HMAC forgery, replay attacks, nonce griefing, DDoS
- **Operational:** Key leakage, RPC censorship, chain reorgs
- For each threat: likelihood, impact, mitigation

### 3. RUNBOOK.md

Operational procedures:

- **Rollback:** How to revert a bad contract upgrade
- **Key rotation:** How to rotate HMAC secret (zero downtime)
- **DLQ handling:** How to process stuck items
- **Degraded mode:** What to do if RPC is down
- **SLOs:** Availability, latency, error rate targets
- **Alert rules:** When to page on-call

---

## 🧪 Grader's Private Chaos Tests

After submission, we will run hidden tests:

1. **Double webhook storm:** 50 duplicate M-PESA callbacks → system must mint exactly once
2. **RPC flakiness:** Drop 20% of RPC calls → retries and DLQ must work
3. **Chain reorg:** Simulate reorg using Anvil → no double-mints
4. **Key rotation:** Change HMAC secret mid-flight per RUNBOOK → system recovers
5. **Live upgrade:** Add a `require()` to contract and perform safe upgrade

---

## 🎬 Screencast Requirement

Record a **10-minute max** walkthrough showing:

1. `docker compose up` from clean state
2. Demo flow: Submit mint intent → M-PESA callback → mint executed
3. Grafana dashboard (show metrics updating)
4. Logs showing retry/backoff on simulated RPC failure
5. DLQ item example

---

## 📝 Submission Checklist

```
/contracts
  ├── ComplianceManager.sol
  ├── UserRegistry.sol
  ├── MintEscrow.sol
  ├── CountryToken.sol         # ERC20 token (use seed.json countryCode)
  ├── USDStablecoin.sol        # Mock ERC20 for testing
  ├── test/
  └── foundry.toml

/api
  ├── src/
  ├── Dockerfile
  └── package.json (or go.mod)

/ops
  ├── docker-compose.yml
  ├── prometheus.yml
  ├── grafana/
  └── alerts.yml

/docs
  ├── ADR.md
  ├── THREAT_MODEL.md
  └── RUNBOOK.md

/scripts
  └── deploy-and-demo.sh

/.github/workflows
  └── ci.yml

deployments.json              # Contract addresses after deployment
seed.json (with your unique values used throughout)
screencast.mp4 (or .webm, max 10min)
```

---

## 🏆 Scoring Rubric (100 Points)

| Area | Points | What We're Looking For |
|------|--------|------------------------|
| **Solidity Correctness & Safety** | 22 | Upgradeability correct; role gating works; events indexed; no obvious reentrancy; fuzz/invariants meaningful |
| **Testing Depth** | 15 | Beyond happy path; edge cases; integration tests; API idempotency/HMAC tests |
| **API Resilience** | 12 | Idempotency keys work; retries deterministic; DLQ operational; RPC failures handled gracefully |
| **Observability** | 12 | Useful metrics exposed; dashboard helps debug; alerts actionable |
| **CI/CD & Reproducibility** | 10 | GitHub Actions green; `docker compose up` works; gas report generated |
| **Security Mindset** | 10 | Threat model thorough; secrets handled properly; replay/DoS mitigations; event design sound |
| **Architecture & Docs** | 10 | ADR clear on trade-offs; diagrams helpful; runbook actionable |
| **Git Hygiene** | 5 | Incremental commits; sensible messages; shows thought process |
| **Live Defense** | 4 | Crisp reasoning under questions; can modify code live |

**Pass bar for Senior:** ≥ 80 points with no red-flag security holes

---

## 🚫 Anti-Cheat Measures

We will detect AI-generated one-shot dumps:

- ✅ Git history must show incremental commits with meaningful messages
- ✅ Your `seed.json` values must appear throughout code (chain ID, token symbols, salts)
- ✅ Live defense: explain decisions, modify code on the spot
- ✅ Tests must go beyond examples (fuzz/property/negative cases)

---

## 🛠️ Getting Started

1. **Load your unique seed:**
   ```bash
   cat seed.json
   # Note your chain ID, country code, token symbols
   ```

2. **Install dependencies:**
   ```bash
   # Foundry
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   
   # API (Node.js example)
   cd api && npm install
   ```

3. **Start building:**
   ```bash
   # Contracts
   forge init contracts
   
   # Tests
   forge test
   
   # API
   npm run dev
   
   # Full stack
   docker compose up
   ```

4. **Commit frequently:**
   ```bash
   git add -A
   git commit -m "feat: implement UserRegistry with risk scoring"
   ```

5. **After deployment, create `deployments.json`:**
   ```json
   {
     "ComplianceManager": "0x...",
     "UserRegistry": "0x...",
     "MintEscrow": "0x...",
     "CountryToken": "0x...",
     "USDStablecoin": "0x..."
   }
   ```
   This file is required at repo root for grader tests.

---

## 🎤 Live Defense Questions (Examples)

During the 30-45 minute defense, expect:

1. "Why UUPS vs Transparent proxy? Show where misuse could brick it and how you avoid that."
2. "Walk me through your idempotency design. What's the dedup key? How long do you retain it?"
3. "If RPC starts returning sporadic `nonce too low`, what's your backoff and recovery?"
4. "Which events would an indexer need to reconstruct state? Why those fields?"
5. "What would you feature-flag if this went to 10× traffic tomorrow?"

---

## 📞 Support

- **Questions about requirements:** Document any ambiguities in your ADR and explain your interpretation
- **Technical blockers:** Document in your submission; we'll evaluate your problem-solving approach
- **Note:** No external support is available during the trial period

---

## 🧠 Evaluation Philosophy

We're not looking for perfection—we're looking for:

- **Production thinking:** Can you ship something that won't fail at 3am?
- **Trade-off clarity:** Do you understand why you chose X over Y?
- **Debugging readiness:** If this breaks in prod, can you figure out why?
- **Security awareness:** Do you think like an attacker?

Good luck! We're excited to see what you build. 🚀

