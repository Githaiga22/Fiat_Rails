#!/bin/bash

# FiatRails Demo Script - One-shot deployment and demonstration
# This script deploys contracts and runs a demo flow

set -e

echo "════════════════════════════════════════════════════════"
echo "       FiatRails Production Trial - Deploy & Demo"
echo "════════════════════════════════════════════════════════"
echo ""

# Load seed.json
CANDIDATE_ID=$(cat seed.json | jq -r .candidateId)
CHAIN_ID=$(cat seed.json | jq -r .chain.chainId)
COUNTRY_CODE=$(cat seed.json | jq -r .tokens.country.countryCode)

echo "Candidate: $CANDIDATE_ID"
echo "Chain ID: $CHAIN_ID"
echo "Country: $COUNTRY_CODE"
echo ""

# Check prerequisites
echo "📋 Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    echo "❌ Docker not found. Please install Docker."
    exit 1
fi

if ! command -v forge &> /dev/null; then
    echo "❌ Foundry not found. Please install Foundry."
    exit 1
fi

if ! command -v node &> /dev/null; then
    echo "❌ Node.js not found. Please install Node.js."
    exit 1
fi

echo "✅ Prerequisites met"
echo ""

# Start services
echo "🚀 Starting services with docker compose..."
docker compose up -d

echo ""
echo "⏳ Waiting for services to be healthy..."
sleep 10

# Wait for Anvil
until curl -s http://localhost:8545 -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' > /dev/null; do
    echo "   Waiting for Anvil..."
    sleep 2
done
echo "✅ Anvil ready"

# Wait for API
until curl -s http://localhost:3000/health > /dev/null; do
    echo "   Waiting for API..."
    sleep 2
done
echo "✅ API ready"

echo ""
echo "📝 Deploying contracts..."
cd contracts

# Deploy (candidate should implement this)
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast

echo "✅ Contracts deployed"
cd ..

echo ""
echo "🧪 Running demo flow..."

# Demo flow (candidate should implement this)
# 1. Setup test user
# 2. Set compliance for user
# 3. Submit mint intent
# 4. Trigger M-PESA callback
# 5. Verify mint executed

echo ""
echo "════════════════════════════════════════════════════════"
echo "                    DEMO COMPLETE"
echo "════════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  - Open Grafana: http://localhost:3001 (admin/admin)"
echo "  - View Prometheus: http://localhost:9090"
echo "  - Check API health: http://localhost:3000/health"
echo "  - View API metrics: http://localhost:3000/metrics"
echo ""
echo "To stop:"
echo "  docker compose down"
echo ""

