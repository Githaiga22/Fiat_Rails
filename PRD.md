# FiatRails Production Trial - Product Requirements Document

## Project Overview
**Goal:** Build a production-ready fiat-to-crypto minting system with compliance checks
**Timeline:** 8-12 hours over 1-2 days
**Success Criteria:** Score ≥80/100 points with no critical security vulnerabilities

---

## 🎯 Milestones & Task Breakdown

### Milestone 1: Project Setup & Foundation (2-3 hours)
**Goal:** Get the development environment ready and understand the architecture

#### 1.1 Environment Setup
- [x] ✅ Review `seed.json` file and note unique values (chain ID: 31382, country code: KES, token symbols: USDT/KES)
- [x] ✅ Install Foundry toolchain (v1.2.3-stable already installed)
- [x] ✅ Initialize Foundry project structure (`forge init contracts`)
- [x] ✅ Set up API project directory (Node.js v22.14.0, package.json created)
- [x] ✅ Install Docker and Docker Compose (Docker v27.5.1 already installed)
- [x] ✅ Create basic `.gitignore` file
- [x] ✅ Initialize git repository if not already done

#### 1.2 Architecture Planning
- [x] ✅ Read through all requirements in README.md, Test-Readme.md, and PRD.md
- [x] ✅ Sketch system architecture diagram (reviewed from README.md)
- [x] ✅ Identify all components and their interactions (reviewed interfaces and openapi.yaml)
- [x] ✅ List all required events and their indexed fields (from IComplianceManager, IMintEscrow)
- [x] ✅ Plan database schema for idempotency keys (reviewed from ADR template)

#### 1.3 Documentation Foundation
- [x] ✅ Create `/docs` directory
- [x] ✅ Create `ADR.md`, `THREAT_MODEL.md`, `RUNBOOK.md` (from templates)
- [x] ✅ Start documenting initial architecture decisions (templates ready to fill)
- [x] ✅ Git commit: "chore: initialize project structure with Foundry and API setup"

---

### Milestone 2: Smart Contracts - Core Implementation (3-4 hours)
**Goal:** Build and test all required smart contracts

#### 2.1 USDStablecoin Mock (15 min)
- [x] ✅ Create `USDStablecoin.sol` - basic ERC20 with 18 decimals
- [x] ✅ Add pre-mint function for testing
- [x] ✅ Write basic unit tests
- [x] ✅ Git commit: "feat: implement USD stablecoin mock"

#### 2.2 CountryToken (20 min)
- [x] ✅ Create `CountryToken.sol` - ERC20 using seed.json country code as symbol
- [x] ✅ Implement minter role mechanism
- [x] ✅ Add 18 decimals
- [x] ✅ Write unit tests for minting permissions
- [x] ✅ Git commit: "feat: implement country token with role-based minting"

#### 2.3 UserRegistry Contract (45 min)
- [x] ✅ Create `UserRegistry.sol`
- [x] ✅ Implement storage for risk scores (uint8, 0-100)
- [x] ✅ Implement storage for attestation hashes
- [x] ✅ Add role-based access control for writes
- [x] ✅ Implement query interface for compliance checks
- [x] ✅ Emit `UserRiskUpdated` event with proper indexing
- [x] ✅ Emit `AttestationRecorded` event with proper indexing
- [x] ✅ Write unit tests (happy path)
- [x] ✅ Write fuzz tests for risk score boundaries
- [x] ✅ Git commit: "feat: implement UserRegistry with risk scoring"

#### 2.4 ComplianceManager Contract (1 hour)
- [x] ✅ Create `ComplianceManager.sol` with UUPS upgradeability
- [x] ✅ Implement role-based access control (ADMIN, COMPLIANCE_OFFICER, UPGRADER)
- [x] ✅ Add Pausable mechanism
- [x] ✅ Write logic to check user compliance status
- [x] ✅ Ensure all events are properly indexed
- [x] ✅ Write unit tests for all roles
- [x] ✅ Write upgrade tests (test upgradeability)
- [x] ✅ Test pause mechanism
- [x] ✅ Document ADR decision: Why UUPS vs Transparent proxy
- [x] ✅ Git commit: "feat: implement ComplianceManager with UUPS upgradeability"

#### 2.5 MintEscrow Contract (1.5 hours)
- [x] ✅ Create `MintEscrow.sol`
- [x] ✅ Implement deposit intent submission
- [x] ✅ Add UserRegistry compliance check before minting
- [x] ✅ Implement 1:1 minting logic for compliant users
- [x] ✅ Add idempotency mechanism (prevent double-execution)
- [x] ✅ Implement refund logic for non-compliant users
- [x] ✅ Emit `MintIntentSubmitted` event
- [x] ✅ Emit `MintExecuted` event
- [x] ✅ Write unit tests for all functions
- [x] ✅ Write integration tests (multi-contract flows)
- [x] ✅ Write fuzz tests for amounts and edge cases
- [x] ✅ Git commits: 11 incremental commits showing natural progression

#### 2.6 Contract Testing & Coverage (45 min)
- [x] ✅ Run all tests: `forge test` (107 tests passing)
- [x] ✅ Generate coverage report: `forge coverage`
- [x] ✅ Ensure >80% test coverage (achieved 94.26%)
- [ ] Generate gas snapshots: `forge snapshot`
- [x] ✅ Add negative test cases (unauthorized access, invalid inputs)
- [ ] Document gas optimization decisions in ADR

---

### Milestone 3: API Service Implementation (3-4 hours)
**Goal:** Build resilient API with idempotency and retry logic

#### 3.1 API Foundation (30 min)
- [x] ✅ Set up Express.js with Node.js ESM
- [x] ✅ Set up environment variables management (dotenv)
- [x] ✅ Configure database connection (SQLite with better-sqlite3)
- [x] ✅ Create database schema for idempotency keys
- [x] ✅ Set up Web3 provider connection (ethers.js v6)
- [x] ✅ Git commits: package.json, config, database, blockchain modules

#### 3.2 HMAC Verification Middleware (30 min)
- [x] ✅ Implement HMAC signature generation function
- [x] ✅ Implement HMAC signature verification middleware
- [x] ✅ Add timestamp freshness check (reject old requests)
- [x] ✅ Write tests for HMAC verification (13 tests passing)
- [x] ✅ Git commits: HMAC utility, middleware, tests

#### 3.3 Idempotency System (45 min)
- [x] ✅ Create idempotency keys table in database
- [x] ✅ Implement idempotency middleware (check X-Idempotency-Key)
- [x] ✅ Store request/response in database
- [x] ✅ Return cached response for duplicate keys
- [x] ✅ Add TTL for cleanup (86400 seconds from seed.json)
- [x] ✅ Git commit: "feat: implement idempotency system with database"

#### 3.4 POST /mint-intents Endpoint (30 min)
- [x] ✅ Create endpoint handler
- [x] ✅ Validate request body (amount, countryCode, txRef, userAddress)
- [x] ✅ Apply idempotency middleware
- [x] ✅ Apply HMAC verification
- [x] ✅ Submit transaction to MintEscrow contract
- [x] ✅ Return intent ID
- [x] ✅ Add error handling with retry queue
- [x] ✅ Git commit: "feat: implement /mint-intents endpoint"

#### 3.5 Retry & DLQ System (1 hour)
- [x] ✅ Implement exponential backoff function (691ms initial, 2x multiplier, 30s max)
- [x] ✅ Create retry queue mechanism (SQLite table)
- [x] ✅ Implement dead-letter queue (DLQ) - JSON file storage
- [x] ✅ Add RPC failure handling (graceful degradation)
- [x] ✅ Write tests for retry logic (8 exponential backoff tests)
- [x] ✅ Git commits: retry system, tests

#### 3.6 POST /callbacks/mpesa Endpoint (45 min)
- [x] ✅ Create webhook endpoint handler
- [x] ✅ Verify HMAC signature (X-Mpesa-Signature header)
- [x] ✅ Check timestamp freshness
- [x] ✅ Check user compliance before minting
- [x] ✅ Call `escrow.executeMint(intentId)` with retry logic
- [x] ✅ Handle RPC failures with backoff
- [x] ✅ Move to DLQ after exhausting retries
- [x] ✅ Git commit: "feat: implement M-PESA callback webhook with retry"

#### 3.7 Health & Metrics Endpoints (30 min)
- [x] ✅ Create GET /health endpoint (service status, RPC connectivity, queue depth)
- [x] ✅ Install Prometheus client library (prom-client)
- [x] ✅ Implement metrics collection (counters, gauges, histograms)
- [x] ✅ Create GET /metrics endpoint (Prometheus format)
- [x] ✅ Add required metrics: RPC requests, mint intents, callbacks, DLQ depth, retries, compliance checks, latency
- [x] ✅ Git commit: "feat: add health and Prometheus metrics endpoints"

---

### Milestone 4: Operations & Observability (2-3 hours)
**Goal:** Docker deployment with monitoring and CI/CD

#### 4.1 Docker Configuration (1 hour)
- [ ] Create Dockerfile for API service
- [ ] Create `docker-compose.yml` with all services:
  - [ ] API service
  - [ ] Anvil (local Ethereum node)
  - [ ] PostgreSQL (or use SQLite)
  - [ ] Redis (optional, for caching)
  - [ ] Prometheus
  - [ ] Grafana
- [ ] Add health checks for all services
- [ ] Configure service dependencies
- [ ] Create `.env.example` file
- [ ] Test: `docker compose up` should start everything
- [ ] Git commit: "ops: add Docker Compose configuration"

#### 4.2 Prometheus Configuration (30 min)
- [ ] Create `ops/prometheus.yml`
- [ ] Configure scrape targets (API /metrics endpoint)
- [ ] Set scrape intervals
- [ ] Add recording rules (optional)
- [ ] Create `ops/alerts.yml` with alert rules
- [ ] Test metrics collection
- [ ] Git commit: "ops: configure Prometheus with alert rules"

#### 4.3 Grafana Dashboard (45 min)
- [ ] Create `ops/grafana/` directory
- [ ] Configure Grafana data source (Prometheus)
- [ ] Create dashboard JSON with panels:
  - [ ] RPC error rate (5m window)
  - [ ] p95 latency for RPC and API
  - [ ] DLQ depth over time
  - [ ] Successful mint rate
  - [ ] Visual alerts for thresholds
- [ ] Add dashboard provisioning config
- [ ] Test dashboard displays metrics
- [ ] Git commit: "ops: create Grafana dashboard with key metrics"

#### 4.4 CI/CD Pipeline (45 min)
- [ ] Create `.github/workflows/ci.yml`
- [ ] Add job: Run Foundry tests
- [ ] Add job: Run Solidity linter (forge fmt --check)
- [ ] Add job: Run API linter (eslint/golint)
- [ ] Add job: Generate gas report (forge snapshot)
- [ ] Add job: Build Docker images
- [ ] Ensure all checks must pass
- [ ] Test CI pipeline runs
- [ ] Git commit: "ci: add GitHub Actions workflow"

---

### Milestone 5: Documentation & Security (2 hours)
**Goal:** Complete all required documentation

#### 5.1 ADR.md - Architecture Decision Records (45 min)
- [ ] Document: UUPS vs Transparent proxy choice
- [ ] Document: Event schema design (which fields indexed, why)
- [ ] Document: Idempotency strategy (storage, TTL, key format)
- [ ] Document: Key management approach (HMAC secrets, private keys)
- [ ] Document: Database choice and schema
- [ ] Document: Retry/backoff parameters
- [ ] Add diagrams if helpful
- [ ] Git commit: "docs: complete architecture decision records"

#### 5.2 THREAT_MODEL.md (45 min)
- [ ] **On-chain threats:**
  - [ ] Reentrancy attacks and mitigations
  - [ ] Replay attacks and mitigations
  - [ ] Role escalation and mitigations
  - [ ] Upgrade bricking and mitigations
- [ ] **Off-chain threats:**
  - [ ] HMAC forgery and mitigations
  - [ ] Replay attacks and mitigations
  - [ ] Nonce griefing and mitigations
  - [ ] DDoS and mitigations
- [ ] **Operational threats:**
  - [ ] Key leakage and mitigations
  - [ ] RPC censorship and mitigations
  - [ ] Chain reorgs and mitigations
- [ ] For each: likelihood, impact, mitigation
- [ ] Git commit: "docs: complete threat model"

#### 5.3 RUNBOOK.md (30 min)
- [ ] Document: How to rollback a bad contract upgrade
- [ ] Document: How to rotate HMAC secret (zero downtime)
- [ ] Document: How to process stuck DLQ items
- [ ] Document: What to do if RPC is down (degraded mode)
- [ ] Define SLOs: Availability, latency, error rate targets
- [ ] Define alert rules: When to page on-call
- [ ] Add troubleshooting steps for common issues
- [ ] Git commit: "docs: complete operational runbook"

---

### Milestone 6: Deployment & Demo (1-2 hours)
**Goal:** Deploy contracts, create deployment script, record screencast

#### 6.1 Deployment Script (30 min)
- [ ] Create `scripts/deploy-and-demo.sh`
- [ ] Script should:
  - [ ] Deploy all contracts to Anvil
  - [ ] Configure contract relationships (grant roles, set addresses)
  - [ ] Pre-mint USD tokens to test users
  - [ ] Create test users in UserRegistry
- [ ] Create `deployments.json` with contract addresses
- [ ] Test script works from clean state
- [ ] Git commit: "scripts: add deployment and demo script"

#### 6.2 End-to-End Testing (30 min)
- [ ] Test complete flow:
  1. Submit mint intent via API
  2. Trigger M-PESA callback
  3. Verify mint executed on-chain
- [ ] Test retry logic with simulated RPC failure
- [ ] Test DLQ with exhausted retries
- [ ] Verify metrics update in Grafana
- [ ] Test idempotency (send duplicate requests)
- [ ] Git commit: "test: verify end-to-end flow"

#### 6.3 Screencast Recording (30 min)
- [ ] Record 10-minute max walkthrough showing:
  1. `docker compose up` from clean state
  2. Demo flow: Submit mint intent → M-PESA callback → mint executed
  3. Grafana dashboard (show metrics updating)
  4. Logs showing retry/backoff on simulated RPC failure
  5. DLQ item example
- [ ] Save as `screencast.mp4` or `screencast.webm`
- [ ] Verify video quality and audio clarity

---

### Milestone 7: Final Review & Submission (1 hour)
**Goal:** Ensure everything is complete and polished

#### 7.1 Code Review (20 min)
- [ ] Review all contract code for security issues
- [ ] Review API code for error handling
- [ ] Check all tests are passing
- [ ] Verify gas snapshots are reasonable
- [ ] Run linters on all code
- [ ] Check test coverage >80%

#### 7.2 Submission Checklist (20 min)
- [ ] Verify directory structure matches requirements
- [ ] Ensure `deployments.json` exists at repo root
- [ ] Ensure `seed.json` values used throughout code
- [ ] Check all documentation files are complete
- [ ] Verify `docker compose up` works from clean state
- [ ] Verify CI/CD pipeline is green
- [ ] Check screencast file is included

#### 7.3 Git History Review (20 min)
- [ ] Review commit history (incremental commits with meaningful messages)
- [ ] Squash any "WIP" or "fix typo" commits
- [ ] Ensure commits show thought process
- [ ] Push to repository
- [ ] Final commit: "chore: prepare submission"

---

## 📊 Progress Tracking

### Estimated Time Per Milestone
- Milestone 1 (Setup): 2-3 hours
- Milestone 2 (Contracts): 3-4 hours
- Milestone 3 (API): 3-4 hours
- Milestone 4 (Operations): 2-3 hours
- Milestone 5 (Documentation): 2 hours
- Milestone 6 (Deployment): 1-2 hours
- Milestone 7 (Review): 1 hour

**Total: 14-19 hours** (fits within 8-12 hour guidance if you're efficient)

### Daily Schedule Suggestion

**Day 1 (6-8 hours):**
- Morning: Milestones 1-2 (Setup + Contracts)
- Afternoon: Milestone 3 (API Service)
- Document decisions in ADR as you go

**Day 2 (6-8 hours):**
- Morning: Milestone 4 (Operations)
- Midday: Milestone 5 (Documentation)
- Afternoon: Milestones 6-7 (Deployment + Review)

---

## 🎯 Critical Success Factors

1. **Security First:** No reentrancy, proper access control, HMAC verification
2. **Idempotency:** Must handle duplicate requests correctly
3. **Resilience:** System must recover from RPC failures
4. **Testing:** >80% coverage with meaningful tests
5. **Documentation:** Clear ADR explaining trade-offs
6. **Git Hygiene:** Incremental commits showing work progression
7. **Reproducibility:** `docker compose up` must work

---

## 🚨 Common Pitfalls to Avoid

- Don't skip tests - they're 15 points
- Don't forget to index events properly
- Don't hardcode values - use seed.json throughout
- Don't one-shot commit everything - show incremental progress
- Don't skip ADR decisions - graders want to see your thinking
- Don't forget nonce management in API
- Don't skip DLQ implementation
- Don't forget to test upgrade mechanism

---

## 📝 Notes Section

Use this space to track your decisions, blockers, and questions as you work:

### Key Decisions
-

### Blockers Encountered
-

### Questions for Live Defense
-

---

## 🎓 Learning Resources

If you need references:
- UUPS Proxy: OpenZeppelin docs
- Foundry: book.getfoundry.sh
- Prometheus metrics: prometheus.io/docs
- HMAC: OWASP cheat sheet
- Idempotency: Stripe API design guide

---

**Remember:** The goal is not perfection, but demonstrating production thinking, trade-off clarity, debugging readiness, and security awareness. Good luck!
