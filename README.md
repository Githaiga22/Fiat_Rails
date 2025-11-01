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