# FiatRails - Production Fiat-to-Crypto Minting System

A production-ready system for handling fiat-to-crypto conversions with integrated compliance checks, built with Solidity smart contracts and a resilient Node.js API service.

## Overview

FiatRails enables secure, compliant conversion of fiat currency to country-specific tokens through:

- **Smart Contract Layer**: Upgradeable EVM contracts with role-based access control and compliance checks
- **API Service**: Resilient backend with idempotency, HMAC verification, and retry mechanisms
- **Observability**: Full Prometheus/Grafana monitoring stack with actionable alerts
- **Production-Ready**: Docker-based deployment with comprehensive testing and operational runbooks


## Architecture

```
┌─────────────┐      ┌──────────────┐      ┌─────────────────┐
│   M-PESA    │─────▶│  API Service │─────▶│ Smart Contracts │
│  (Webhook)  │      │  (Node.js)   │      │   (Solidity)    │
└─────────────┘      └──────────────┘      └─────────────────┘
                            │                       │
                            ▼                       ▼
                     ┌──────────────┐      ┌─────────────────┐
                     │  PostgreSQL  │      │  EVM Network    │
                     │ (Idempotency)│      │    (Anvil)      │
                     └──────────────┘      └─────────────────┘
                            │
                            ▼
                     ┌──────────────┐
                     │  Prometheus  │
                     │   Grafana    │
                     └──────────────┘
```


## Features

### Smart Contracts

- **ComplianceManager**: Upgradeable (UUPS) contract with emergency pause functionality
- **UserRegistry**: Risk scoring (0-100) and attestation management
- **MintEscrow**: Idempotent minting with automatic compliance verification
- **CountryToken**: ERC20 token representing country-specific stablecoin
- **USDStablecoin**: Mock USDC for testing


### API Service

- **POST /mint-intents**: Submit new mint requests with idempotency support
- **POST /callbacks/mpesa**: Process M-PESA payment confirmations
- **GET /health**: Service health and connectivity status
- **GET /metrics**: Prometheus-formatted metrics



### Security Features

- HMAC signature verification for all webhooks
- Timestamp-based replay attack prevention
- Role-based access control on all contracts
- Pausable contracts for emergency stops
- Comprehensive audit trail via indexed events

### Resilience

- Exponential backoff retry mechanism
- Dead-letter queue for failed operations
- Graceful RPC failure handling
- Nonce management for transaction ordering
- Request deduplication via idempotency keys


## Quick Start

### Prerequisites

- Docker & Docker Compose
- Node.js 18+ (for local development)
- Foundry (for smart contract development)

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/Githaiga22/FiatRails.git
   cd fiatrails-trial
   ```

2. **Configure environment:**
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

3. **Start the entire stack:**
   ```bash
   docker compose up
   ```

4. **Deploy contracts and run demo:**
   ```bash
   ./scripts/deploy-and-demo.sh
   ```

The system will be available at:
- API: http://localhost:3000
- Grafana: http://localhost:3001 (admin/admin)
- Prometheus: http://localhost:9090

## Development

### Smart Contracts

```bash
cd contracts

# Install dependencies
forge install

# Run tests
forge test

# Run tests with coverage
forge coverage

# Generate gas report
forge snapshot

# Run linter
forge fmt --check
```

### API Service

```bash
cd api

# Install dependencies
npm install

# Run in development mode
npm run dev

# Run tests
npm test

# Run linter
npm run lint

# Build for production
npm run build
```

## Testing

The project includes comprehensive testing:

- **Unit Tests**: Individual contract and function testing
- **Fuzz Tests**: Random input validation
- **Invariant Tests**: System-wide property verification
- **Integration Tests**: Multi-contract flow testing
- **API Tests**: Endpoint testing with idempotency verification

**Test Coverage**: >80% across all contracts

## Monitoring

### Key Metrics

- `fiatrails_rpc_requests_total`: RPC call volume by method and status
- `fiatrails_rpc_duration_seconds`: RPC latency percentiles
- `fiatrails_mint_intents_total`: Mint request volume
- `fiatrails_callbacks_total`: Webhook processing status
- `fiatrails_dlq_depth`: Dead-letter queue size
- `fiatrails_compliance_checks_total`: Compliance check results

### Grafana Dashboard

Pre-configured dashboard includes:
- RPC error rate (5-minute rolling window)
- API p95 latency
- Mint success rate
- DLQ depth alerts
- Compliance check distribution

## Documentation

- **[ADR.md](./docs/ADR.md)**: Architecture decisions and trade-offs
- **[THREAT_MODEL.md](./docs/THREAT_MODEL.md)**: Security analysis and mitigations
- **[RUNBOOK.md](./docs/RUNBOOK.md)**: Operational procedures and troubleshooting

## Project Structure

```
.
├── contracts/              # Solidity smart contracts
│   ├── src/
│   │   ├── ComplianceManager.sol
│   │   ├── UserRegistry.sol
│   │   ├── MintEscrow.sol
│   │   ├── CountryToken.sol
│   │   └── USDStablecoin.sol
│   └── test/              # Foundry tests
├── api/                   # Node.js API service
│   ├── src/
│   │   ├── routes/
│   │   ├── middleware/
│   │   ├── services/
│   │   └── utils/
│   └── test/
├── ops/                   # Operations configuration
│   ├── docker-compose.yml
│   ├── prometheus.yml
│   ├── alerts.yml
│   └── grafana/
├── docs/                  # Documentation
│   ├── ADR.md
│   ├── THREAT_MODEL.md
│   └── RUNBOOK.md
├── scripts/               # Deployment and utility scripts
│   └── deploy-and-demo.sh
├── .github/
│   └── workflows/
│       └── ci.yml         # CI/CD pipeline
├── deployments.json       # Contract addresses
├── seed.json             # Project configuration
└── PRD.md                # Product requirements
```

## API Usage Examples

### Submit Mint Intent

```bash
curl -X POST http://localhost:3000/mint-intents \
  -H "Content-Type: application/json" \
  -H "X-Idempotency-Key: unique-key-123" \
  -H "X-Signature: hmac-signature" \
  -d '{
    "userId": "0x1234...",
    "amount": "100000000000000000000",
    "countryCode": "KES"
  }'
```

### Simulate M-PESA Callback

```bash
curl -X POST http://localhost:3000/callbacks/mpesa \
  -H "Content-Type: application/json" \
  -H "X-Mpesa-Signature: hmac-signature" \
  -d '{
    "txRef": "MPESA123456",
    "intentId": "0xabcd...",
    "amount": "100.00",
    "timestamp": 1234567890
  }'
```

## CI/CD

The project uses GitHub Actions for continuous integration:

- Smart contract testing (Foundry)
- API testing (Jest/Mocha)
- Linting (Solidity & TypeScript)
- Gas report generation
- Docker image builds

All checks must pass before merging.

## Security

This project implements defense-in-depth security:

- **Smart Contracts**: Audited for reentrancy, access control, and upgradeability issues
- **API**: HMAC verification, rate limiting, input validation
- **Operations**: Secret management, network isolation, monitoring

For security concerns, please review [THREAT_MODEL.md](./docs/THREAT_MODEL.md).

## Operational Procedures

### Emergency Pause

```bash
# Pause the MintEscrow contract
cast send $MINT_ESCROW "pause()" --private-key $ADMIN_KEY

# Unpause when issue is resolved
cast send $MINT_ESCROW "unpause()" --private-key $ADMIN_KEY
```

### Process DLQ Items

```bash
# View DLQ items
npm run dlq:list

# Retry specific item
npm run dlq:retry <item-id>

# Clear DLQ
npm run dlq:clear
```

### Key Rotation

See [RUNBOOK.md](./docs/RUNBOOK.md) for zero-downtime key rotation procedure.

## Performance

- **RPC Latency**: p95 < 200ms
- **API Latency**: p95 < 100ms
- **Mint Success Rate**: >99.5%
- **Idempotency**: 100% duplicate prevention
- **Uptime SLO**: 99.9%

## License

MIT

## Contributing

This is a production trial project. For questions or issues, please refer to the documentation or create an issue.

## Acknowledgments

Built with:
- [Foundry](https://getfoundry.sh/) - Ethereum development toolkit
- [OpenZeppelin](https://openzeppelin.com/) - Secure smart contract library
- [Express.js](https://expressjs.com/) - Web framework
- [Prometheus](https://prometheus.io/) - Monitoring system
- [Grafana](https://grafana.com/) - Observability platform

---

**Note**: This system is designed for demonstration purposes as part of a technical assessment. For production deployment, additional security audits and compliance reviews are recommended.
