# FiatRails - Production-Ready Fiat-to-Crypto Minting Protocol

A complete, production-ready system for compliant fiat-to-crypto conversions with integrated compliance checks, resilient architecture, and comprehensive operational tooling.

[![Tests](https://github.com/Githaiga22/FiatRails/actions/workflows/ci.yml/badge.svg)](https://github.com/Githaiga22/FiatRails/actions)
[![Coverage](https://img.shields.io/badge/coverage-94.26%25-brightgreen)]()
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Overview

FiatRails is an end-to-end protocol that enables secure, compliant conversion of fiat currency (via M-PESA) to blockchain-native country tokens. The system enforces compliance checks at every step, handles payment provider webhooks with full idempotency guarantees, and provides production-grade monitoring and operational tooling.

### Key Components

- **Smart Contract Layer**: UUPS upgradeable contracts with role-based access control, compliance orchestration, and idempotent minting
- **API Service**: Resilient Node.js backend with HMAC authentication, exponential backoff retries, and dead-letter queue handling
- **Observability Stack**: Complete Prometheus/Grafana monitoring with pre-configured dashboards and alerting rules
- **Operations**: Docker Compose deployment with health checks, graceful degradation, and comprehensive runbooks

---

## Architecture

```
┌──────────────┐      HMAC        ┌─────────────────┐      Web3      ┌──────────────────┐
│   M-PESA     │  Verification    │   API Service   │   Provider     │ Smart Contracts  │
│   Webhook    ├─────────────────▶│   (Node.js)     ├───────────────▶│   (Solidity)     │
└──────────────┘                  └────────┬────────┘                └────────┬─────────┘
                                           │                                  │
                                           │ Idempotency                      │ On-chain
                                           │   Check                          │  Events
                                           ▼                                  ▼
                                  ┌─────────────────┐               ┌──────────────────┐
                                  │    Database     │               │   EVM Network    │
                                  │ (SQLite/Pg SQL) │               │     (Anvil)      │
                                  │  - Dedup Keys   │               │  - UserRegistry  │
                                  │  - Retry Queue  │               │  - MintEscrow    │
                                  │  - DLQ          │               │  - Compliance    │
                                  └────────┬────────┘               └──────────────────┘
                                           │
                                           │ Metrics
                                           ▼
                                  ┌─────────────────┐
                                  │   Prometheus    │
                                  │     Grafana     │
                                  │   Dashboards    │
                                  └─────────────────┘
```

### Architecture Highlights

- **Compliance-First**: Every mint transaction validated against UserRegistry with risk scoring
- **Idempotency**: UUID-based deduplication with 24-hour TTL prevents double-mints
- **Retry Logic**: Exponential backoff (691ms initial, 2x multiplier, 30s max) handles RPC failures
- **Dead-Letter Queue**: Failed transactions persisted for manual review and replay
- **Event-Driven**: Indexed on-chain events enable efficient off-chain indexing and reconciliation

---

## System Deliverables

This implementation includes all components specified in the production trial requirements:

### 1. On-Chain Components (Solidity + Foundry)

#### Smart Contracts

| Contract | Description | Features |
|----------|-------------|----------|
| **ComplianceManager** | UUPS upgradeable compliance orchestrator | • Role-based access (ADMIN, COMPLIANCE_OFFICER, UPGRADER)<br>• Pausable for emergency stops<br>• Indexed events for off-chain processing |
| **UserRegistry** | User compliance data storage | • Risk score (0-100) per user<br>• Attestation hash storage<br>• Compliance query interface (verified + risk ≤83 + attestation) |
| **MintEscrow** | Core minting logic with escrow | • USD stablecoin deposit acceptance<br>• Compliance-gated 1:1 minting<br>• Idempotency via intent IDs<br>• Refund mechanism for non-compliant users |
| **CountryToken** | ERC20 country-specific token | • Symbol from seed.json (KES)<br>• 18 decimals<br>• Role-based minting |
| **USDStablecoin** | Mock USDC for testing | • Pre-mint capability<br>• 18 decimals |

#### Events (Indexed for Off-Chain Processing)

```solidity
event UserRiskUpdated(
    address indexed user,
    uint8 newRiskScore,
    address indexed updatedBy,
    uint256 timestamp
);

event AttestationRecorded(
    address indexed user,
    bytes32 indexed attestationHash,
    bytes32 attestationType,
    address indexed recordedBy
);

event MintIntentSubmitted(
    bytes32 indexed intentId,
    address indexed user,
    uint256 amount,
    bytes32 indexed countryCode,
    bytes32 txRef
);

event MintExecuted(
    bytes32 indexed intentId,
    address indexed user,
    uint256 amount,
    bytes32 indexed countryCode,
    bytes32 txRef
);
```

#### Testing

- **107 tests passing** across all contracts
- **94.26% test coverage** (exceeds 80% requirement)
- **Test types**:
  - Unit tests for individual functions
  - Fuzz tests (257 runs each) for input validation
  - Integration tests for multi-contract flows
  - Upgrade tests for UUPS mechanism
  - Negative tests for unauthorized access

```bash
forge test                    # Run all tests
forge coverage                # Generate coverage report
forge snapshot                # Generate gas snapshots
```

### 2. Off-Chain API Service (Node.js)

#### Endpoints

| Endpoint | Method | Description | Security |
|----------|--------|-------------|----------|
| `/mint-intents` | POST | Submit new mint request | HMAC signature + idempotency key |
| `/callbacks/mpesa` | POST | Process M-PESA payment webhook | HMAC signature + timestamp freshness |
| `/health` | GET | Service health check | Public |
| `/metrics` | GET | Prometheus metrics | Public |

#### Resilience Features

- **Idempotency**: Database-backed deduplication (24h TTL from seed.json)
- **Retry Logic**: Exponential backoff with configurable parameters
- **Dead-Letter Queue**: File-based persistence for exhausted retries
- **RPC Failure Handling**: Graceful degradation, no crashes
- **Nonce Management**: Sequential transaction ordering with `pending` nonce strategy

#### API Testing

- **35 tests passing**
- **Test coverage**:
  - HMAC verification (valid/invalid signatures, expired timestamps)
  - Exponential backoff calculations
  - Idempotency key handling

```bash
cd api && npm test            # Run API tests
```

### 3. Operations & Observability

#### Docker Deployment

```bash
docker compose up             # Start all services
```

**Services included**:
- API service (Node.js)
- Anvil (local Ethereum node)
- Prometheus (metrics collection)
- Grafana (visualization)
- Proper health checks and dependencies configured

#### Prometheus Metrics

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

Pre-configured panels:
- RPC error rate (5-minute rolling window)
- p95 latency for RPC and API calls
- DLQ depth over time
- Successful mint rate
- Visual alerts when thresholds exceeded

Access: http://localhost:3001 (admin/admin)

#### CI/CD Pipeline

GitHub Actions workflow (`.github/workflows/ci.yml`):
-  Run Foundry tests (107 tests)
-  Run API tests (35 tests)
-  Solidity linting (`forge fmt --check`)
-  Gas report generation (`forge snapshot`)
-  Docker image builds

---

## Documentation

Comprehensive operational documentation included:

| Document | Purpose |
|----------|---------|
| **[ADR.md](./docs/ADR.md)** | Architecture Decision Records explaining trade-offs:<br>• UUPS vs Transparent proxy rationale<br>• Event schema design<br>• Idempotency strategy<br>• Key management approach<br>• Database and retry parameters |
| **[THREAT_MODEL.md](./docs/THREAT_MODEL.md)** | Security analysis covering:<br>• On-chain threats (reentrancy, replay, role escalation)<br>• Off-chain threats (HMAC forgery, DDoS, nonce griefing)<br>• Operational threats (key leakage, RPC censorship)<br>• Likelihood, impact, and mitigations for each |
| **[RUNBOOK.md](./docs/RUNBOOK.md)** | Operational procedures:<br>• Contract upgrade rollback<br>• HMAC secret rotation (zero downtime)<br>• DLQ processing<br>• Degraded mode operations<br>• SLOs and alert response |
| **[TESTING.md](./docs/TESTING.md)** | Testing guide including:<br>• Automated test documentation<br>• Manual testing procedures (retry/DLQ)<br>• Failure scenario simulations |
| **[FINAL_REVIEW.md](./docs/FINAL_REVIEW.md)** | Comprehensive code review:<br>• Security assessment<br>• Test coverage analysis<br>• Submission checklist verification |

---

## Quick Start

### Prerequisites

- **Docker & Docker Compose**: Required for running the full stack
- **Node.js 18+**: For local API development
- **Foundry**: For smart contract development ([installation](https://getfoundry.sh/))

### Installation & Deployment

```bash
# 1. Clone the repository
git clone https://github.com/Githaiga22/FiatRails.git
cd FiatRails

# 2. Start services
docker compose up -d

# 3. Deploy contracts and run demo
./scripts/deploy-and-demo.sh
```

The deployment script will:
1.  Start all Docker services (API, Anvil, Prometheus, Grafana)
2.  Deploy all smart contracts to Anvil
3.  Configure contract relationships (roles, addresses)
4.  Pre-mint USD tokens to test users
5.  Create compliant test users in UserRegistry
6.  Execute a complete mint flow demonstration
7.  Generate `deployments.json` with contract addresses

**Services will be available at:**
- API: http://localhost:3000
- Grafana: http://localhost:3001 (admin/admin)
- Prometheus: http://localhost:9090
- Health: http://localhost:3000/health
- Metrics: http://localhost:3000/metrics

---

## Development Workflow

### Smart Contract Development

```bash
cd contracts

# Install dependencies
forge install

# Run tests
forge test                     # All tests
forge test -vvv                # Verbose output
forge test --match-test testMintFlow  # Specific test

# Check coverage
forge coverage

# Generate gas report
forge snapshot

# Format code
forge fmt
forge fmt --check              # Verify formatting
```

### API Development

```bash
cd api

# Install dependencies
npm install

# Development mode (with auto-reload)
npm run dev

# Run tests
npm test

# Production mode
npm start
```

### End-to-End Testing

```bash
# Ensure services are running
docker compose up -d

# Run complete E2E test suite
node scripts/e2e-test.js
```

**E2E test scenarios**:
1. Complete mint flow (intent → callback → on-chain verification)
2. Idempotency protection (duplicate requests with same key)
3. Non-compliant user rejection
4. Health and metrics endpoint validation

---

## Usage Examples

### Using the API Helper Script

The project includes an HMAC-authenticated helper script for testing:

```bash
# Submit a mint intent
node scripts/api-helper.js submit-intent \
  0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
  1000000000000000000 \
  MPESA-TEST-123

# Trigger M-PESA callback
node scripts/api-helper.js trigger-callback \
  MPESA-TEST-123 \
  0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
  1000000000000000000

# Check health
node scripts/api-helper.js health
```

### Direct API Calls (with HMAC)

```bash
# Submit mint intent
curl -X POST http://localhost:3000/mint-intents \
  -H "Content-Type: application/json" \
  -H "X-Idempotency-Key: $(uuidgen)" \
  -H "X-Signature: <hmac-signature>" \
  -H "X-Timestamp: $(date +%s)" \
  -d '{
    "userId": "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
    "amount": "1000000000000000000",
    "countryCode": "KES",
    "transactionRef": "MPESA-TEST-123"
  }'

# Check metrics
curl http://localhost:3000/metrics
```

### Interacting with Contracts

```bash
# Load contract addresses
export COUNTRY_TOKEN=$(cat deployments.json | jq -r '.countryToken')
export USER_REGISTRY=$(cat deployments.json | jq -r '.userRegistry')
export MINT_ESCROW=$(cat deployments.json | jq -r '.mintEscrow')

# Check user balance
cast call $COUNTRY_TOKEN "balanceOf(address)(uint256)" \
  0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
  --rpc-url http://localhost:8545

# Check user compliance
cast call $USER_REGISTRY "isCompliant(address)(bool)" \
  0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
  --rpc-url http://localhost:8545

# Get intent status
cast call $MINT_ESCROW "getIntentStatus(bytes32)(uint8)" \
  0x... \
  --rpc-url http://localhost:8545
```

---

## Project Structure

```
FiatRails/
├── contracts/                   # Smart contracts (Foundry)
│   ├── src/
│   │   ├── ComplianceManager.sol      # UUPS upgradeable compliance
│   │   ├── UserRegistry.sol           # Risk scoring & attestations
│   │   ├── MintEscrow.sol             # Core minting logic
│   │   ├── CountryToken.sol           # ERC20 country token
│   │   └── USDStablecoin.sol          # Mock USDC
│   ├── test/                    # Foundry tests (107 tests)
│   ├── script/                  # Deployment scripts
│   │   └── Deploy.s.sol
│   ├── IComplianceManager.sol   # Interface definitions
│   ├── IMintEscrow.sol
│   ├── IUserRegistry.sol
│   └── foundry.toml
│
├── api/                         # Node.js API service
│   ├── src/
│   │   ├── routes/              # Endpoint handlers
│   │   │   ├── mintIntents.js
│   │   │   ├── callbacks.js
│   │   │   └── health.js
│   │   ├── middleware/          # HMAC & idempotency
│   │   │   ├── hmacVerification.js
│   │   │   └── idempotency.js
│   │   ├── services/            # Retry & metrics
│   │   │   └── retry.js
│   │   ├── blockchain.js        # Web3 provider
│   │   ├── database.js          # SQLite setup
│   │   ├── config.js            # Load seed.json
│   │   └── index.js             # Express app
│   ├── test/                    # API tests (35 tests)
│   ├── Dockerfile
│   └── package.json
│
├── ops/                         # Operations configuration
│   ├── prometheus.yml           # Metrics scraping config
│   ├── alerts.yml               # Alert rules
│   └── grafana/
│       ├── provisioning/
│       └── dashboards/
│           └── fiatrails.json   # Pre-built dashboard
│
├── docs/                        # Documentation
│   ├── ADR.md                   # Architecture decisions
│   ├── THREAT_MODEL.md          # Security analysis
│   ├── RUNBOOK.md               # Operational procedures
│   ├── TESTING.md               # Testing guide
│   └── FINAL_REVIEW.md          # Code review summary
│
├── scripts/                     # Utility scripts
│   ├── deploy-and-demo.sh       # Complete deployment + demo
│   ├── api-helper.js            # HMAC-authenticated API client
│   └── e2e-test.js              # End-to-end test suite
│
├── .github/
│   └── workflows/
│       └── ci.yml               # CI/CD pipeline
│
├── docker-compose.yml           # Multi-service orchestration
├── deployments.json             # Contract addresses (generated)
├── seed.json                    # Project configuration
└── README.md                    # This file
```

---

## Configuration (`seed.json`)

All system parameters are derived from `seed.json`:

```json
{
  "candidateId": "githaiga-munene",
  "chain": {
    "chainId": 31382,
    "rpcUrl": "https://rpc.sepolia-api.lisk.com"
  },
  "tokens": {
    "country": {
      "countryCode": "KES",
      "name": "Kenyan Shilling Token",
      "symbol": "KES"
    }
  },
  "security": {
    "maxRiskScore": 83,
    "timestampWindow": 300
  },
  "retry": {
    "initialBackoff": 691,
    "maxBackoff": 30000,
    "multiplier": 2,
    "maxRetries": 5
  },
  "idempotency": {
    "ttl": 86400
  },
  "secrets": {
    "hmacSalt": "...",
    "webhookSecret": "..."
  }
}
```

**Usage throughout codebase**:
- Chain ID used in deployment scripts
- Country code used as token symbol
- Max risk score enforced in UserRegistry
- Retry parameters used in API backoff logic
- Secrets used for HMAC verification

---

## Monitoring & Observability

### Key Metrics

Access metrics at http://localhost:3000/metrics

#### RPC Metrics
- `fiatrails_rpc_requests_total` - Total RPC calls by method and status
- `fiatrails_rpc_duration_seconds` - RPC latency histogram (p50, p95, p99)
- `fiatrails_rpc_errors_total` - RPC error counts by error type

#### Business Metrics
- `fiatrails_mint_intents_total` - Mint requests by status
- `fiatrails_callbacks_total` - Webhook processing counts
- `fiatrails_compliance_checks_total` - Compliance check results

#### Operational Metrics
- `fiatrails_dlq_depth` - Current dead-letter queue size
- `fiatrails_retry_attempts_total` - Retry attempt counts
- `fiatrails_idempotency_hits_total` - Duplicate request detection

### Grafana Dashboard

Pre-configured dashboard includes:

1. **RPC Health Panel**
   - Error rate (5m window) with alert threshold at 10%
   - p95 latency with alert threshold at 2s

2. **Business Metrics Panel**
   - Successful mint rate
   - Compliance check distribution
   - Callback processing rate

3. **Queue Health Panel**
   - DLQ depth over time with alert threshold at 10 items
   - Retry attempt distribution

4. **Alerts Panel**
   - Visual indicators when thresholds exceeded
   - Links to relevant runbook procedures

### Alert Rules

Prometheus alerts configured in `ops/alerts.yml`:

- **HighRPCErrorRate**: RPC error rate >10% for 2+ minutes (CRITICAL)
- **DLQGrowing**: DLQ depth >10 items for 5+ minutes (CRITICAL)
- **SlowRPCCalls**: p95 RPC latency >2s for 5+ minutes (WARNING)
- **NoSuccessfulMints**: Zero successful mints in 10 minutes (WARNING)

---

## Operational Procedures

### Emergency Pause

```bash
# Pause ComplianceManager (blocks all compliance checks)
cast send $COMPLIANCE_MANAGER "pause()" \
  --private-key $ADMIN_KEY \
  --rpc-url http://localhost:8545

# Unpause when issue resolved
cast send $COMPLIANCE_MANAGER "unpause()" \
  --private-key $ADMIN_KEY \
  --rpc-url http://localhost:8545
```

### Contract Upgrade (UUPS)

```bash
# 1. Deploy new implementation
forge script script/DeployV2.s.sol --rpc-url http://localhost:8545 --broadcast

# 2. Upgrade proxy
cast send $COMPLIANCE_MANAGER "upgradeTo(address)" $NEW_IMPL \
  --private-key $UPGRADER_KEY \
  --rpc-url http://localhost:8545

# 3. Verify upgrade
cast call $COMPLIANCE_MANAGER "implementation()(address)" \
  --rpc-url http://localhost:8545
```

For rollback procedures, see [RUNBOOK.md](./docs/RUNBOOK.md#contract-upgrade-rollback).

### DLQ Processing

```bash
# View DLQ items
ls -la api/dlq/
cat api/dlq/*.json | jq .

# Manual replay after RPC restoration
node scripts/api-helper.js trigger-callback \
  $TX_REF $USER_ADDRESS $AMOUNT
```

For detailed DLQ procedures, see [RUNBOOK.md](./docs/RUNBOOK.md#dead-letter-queue-processing).

### Key Rotation (Zero Downtime)

See [RUNBOOK.md](./docs/RUNBOOK.md#hmac-secret-rotation) for the complete zero-downtime HMAC secret rotation procedure.

---

## Security Considerations

### Smart Contract Security

-  **Reentrancy Protection**: All state-changing functions use `nonReentrant` modifier
-  **Access Control**: Role-based permissions (ADMIN, EXECUTOR, COMPLIANCE_OFFICER, UPGRADER)
-  **Upgrade Safety**: UUPS pattern with authorization checks, initialization guards
-  **Idempotency**: Intent IDs prevent double-execution
-  **Input Validation**: Amount checks, country code validation, zero-address protection

### API Security

-  **HMAC Verification**: SHA-256 HMAC with timing-safe comparison
-  **Timestamp Freshness**: 5-minute window (from seed.json) prevents replay attacks
-  **Idempotency Keys**: UUID-based deduplication with 24-hour TTL
-  **Error Handling**: No sensitive information leaked in error responses
-  **Input Validation**: Amount limits, country code checks, required field verification

### Operational Security

-  **Secret Management**: All secrets in seed.json or environment variables
-  **Network Isolation**: Docker network segmentation
-  **Monitoring**: Comprehensive metrics and alerting
-  **Audit Trail**: Indexed events for all state changes

For complete threat analysis, see [THREAT_MODEL.md](./docs/THREAT_MODEL.md).

---

## Performance & SLOs

### Service Level Objectives

| Metric | Target | Measurement Window |
|--------|--------|-------------------|
| Availability | 99.9% | 30 days |
| API p95 Latency | <500ms | 5 minutes |
| RPC p95 Latency | <2s | 5 minutes |
| Mint Success Rate | >95% | 1 hour |
| RPC Error Rate | <5% | 5 minutes |

### Gas Optimization

Contract gas usage (from `forge snapshot`):
- MintEscrow.submitIntent: ~120k gas
- MintEscrow.executeMint: ~180k gas
- UserRegistry.updateUser: ~50k gas

---

## Testing

### Test Coverage Summary

- **Smart Contracts**: 107 tests, 94.26% coverage
- **API Service**: 35 tests, comprehensive coverage
- **End-to-End**: 4 complete flow scenarios

### Running Tests

```bash
# Smart contract tests
cd contracts && forge test

# API tests
cd api && npm test

# E2E tests (requires running services)
docker compose up -d
node scripts/e2e-test.js
```

### Manual Testing

For manual testing procedures (retry logic, DLQ processing), see [TESTING.md](./docs/TESTING.md#manual-testing-procedures).

---

## CI/CD

GitHub Actions pipeline runs on every push:

```yaml
 Smart contract tests (Foundry)
 API tests (Node.js)
 Solidity linting (forge fmt)
 Gas report generation
 Docker image builds
```

All checks must pass before merging. See `.github/workflows/ci.yml` for details.

---

## Troubleshooting

### Common Issues

#### "nonce too low" Error
**Solution**: API uses `pending` nonce strategy. Check for stuck transactions:
```bash
cast tx-status $TX_HASH --rpc-url http://localhost:8545
```

#### Grafana Shows "No data"
**Solution**: Verify Prometheus is scraping metrics:
```bash
curl http://localhost:9090/api/v1/targets | jq .
curl http://localhost:3000/metrics
```

#### DLQ Growing
**Solution**: Check RPC connectivity and process DLQ items:
```bash
# Check RPC
cast block-number --rpc-url http://localhost:8545

# Process DLQ
ls api/dlq/ && cat api/dlq/*.json | jq .
```

For comprehensive troubleshooting, see [RUNBOOK.md](./docs/RUNBOOK.md#common-issues--fixes).

---

## Deployment to Production

### Pre-Deployment Checklist

- [ ] External security audit completed
- [ ] Load testing performed
- [ ] Backup and disaster recovery procedures tested
- [ ] Key management system configured (e.g., AWS KMS)
- [ ] Multi-region deployment planned
- [ ] Monitoring and alerting verified
- [ ] On-call rotation established

### Production Deployment

1. Deploy contracts to target network (e.g., Lisk Sepolia)
2. Update `seed.json` with production RPC URL
3. Configure production database (PostgreSQL recommended)
4. Set up secret management (AWS Secrets Manager, HashiCorp Vault)
5. Deploy API service with auto-scaling
6. Configure load balancer and health checks
7. Set up log aggregation (ELK, Datadog, etc.)
8. Verify all monitoring and alerts

For production deployment guide, contact the development team.

---

## License

MIT License - see [LICENSE](LICENSE) for details.

---

## Contributing

This project was built as a production trial assessment. For questions, issues, or contributions:

1. Review existing documentation in `/docs`
2. Check troubleshooting guide in RUNBOOK.md
3. Create an issue with detailed context
4. Follow existing code style and testing patterns

---

## Acknowledgments

Built with industry-standard tools and libraries:

- **[Foundry](https://getfoundry.sh/)** - Fast Ethereum development toolkit
- **[OpenZeppelin](https://openzeppelin.com/)** - Secure smart contract library
- **[Express.js](https://expressjs.com/)** - Minimalist web framework
- **[ethers.js](https://ethers.org/)** - Ethereum library
- **[Prometheus](https://prometheus.io/)** - Monitoring and alerting
- **[Grafana](https://grafana.com/)** - Metrics visualization
- **[Docker](https://www.docker.com/)** - Containerization platform

---

## Contact & Support

**Developer**: Allan Robinson 

**Email**: [allan](allangithaiga5@gmail.com) 

**GitHub**: [@Githaiga22](https://github.com/Githaiga22)

For operational issues in production, refer to the on-call procedures in [RUNBOOK.md](./docs/RUNBOOK.md#emergency-contacts).

---

**Note**: This system demonstrates production-ready architecture and practices. For live deployment handling real financial transactions, additional legal compliance, security audits, and regulatory approvals are required.

**Status**:  Ready for technical evaluation and live defense.
