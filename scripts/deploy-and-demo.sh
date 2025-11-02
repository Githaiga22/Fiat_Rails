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

# Anvil default accounts (pre-funded with 10000 ETH each)
DEPLOYER="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"  # Account #0
TEST_USER="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"    # Account #1
DEPLOYER_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
TEST_USER_KEY="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"

echo "Using Anvil test accounts:"
echo "  Deployer: $DEPLOYER"
echo "  Test User: $TEST_USER"
echo ""

# Deploy contracts
echo "Deploying contracts to Anvil..."
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --private-key $DEPLOYER_KEY --broadcast --silent

# Extract deployed addresses from broadcast folder
BROADCAST_FILE=$(ls -t broadcast/Deploy.s.sol/31382/run-latest.json 2>/dev/null | head -1)

if [ -f "$BROADCAST_FILE" ]; then
    USD_STABLECOIN=$(jq -r '.transactions[] | select(.contractName == "USDStablecoin") | .contractAddress' "$BROADCAST_FILE")
    COUNTRY_TOKEN=$(jq -r '.transactions[] | select(.contractName == "CountryToken") | .contractAddress' "$BROADCAST_FILE")
    USER_REGISTRY=$(jq -r '.transactions[] | select(.contractName == "UserRegistry") | .contractAddress' "$BROADCAST_FILE")
    COMPLIANCE_MANAGER=$(jq -r '.transactions[] | select(.contractName == "ERC1967Proxy") | .contractAddress' "$BROADCAST_FILE" | head -1)
    MINT_ESCROW=$(jq -r '.transactions[] | select(.contractName == "MintEscrow") | .contractAddress' "$BROADCAST_FILE")

    echo "Deployed addresses:"
    echo "  USDStablecoin: $USD_STABLECOIN"
    echo "  CountryToken: $COUNTRY_TOKEN"
    echo "  UserRegistry: $USER_REGISTRY"
    echo "  ComplianceManager: $COMPLIANCE_MANAGER"
    echo "  MintEscrow: $MINT_ESCROW"

    # Update deployments.json
    cd ..
    cat > deployments.json << EOF
{
  "deployer": "$DEPLOYER",
  "usdStablecoin": "$USD_STABLECOIN",
  "countryToken": "$COUNTRY_TOKEN",
  "userRegistry": "$USER_REGISTRY",
  "complianceManager": "$COMPLIANCE_MANAGER",
  "mintEscrow": "$MINT_ESCROW",
  "network": "anvil-local",
  "chainId": $CHAIN_ID,
  "rpcUrl": "http://localhost:8545",
  "timestamp": $(date +%s)
}
EOF
    echo ""
    echo "✅ deployments.json updated"
else
    echo "❌ Failed to find deployment broadcast file"
    cd ..
    exit 1
fi

echo "✅ Contracts deployed"

echo ""
echo "🧪 Running demo flow..."
echo ""

# 1. Pre-mint USD tokens to test user
echo "1️⃣  Pre-minting 10,000 USDT to test user..."
MINT_AMOUNT="10000000000000000000000"  # 10,000 tokens (18 decimals)
cast send $USD_STABLECOIN "mint(address,uint256)" $TEST_USER $MINT_AMOUNT \
    --rpc-url http://localhost:8545 --private-key $DEPLOYER_KEY > /dev/null 2>&1

USD_BALANCE=$(cast call $USD_STABLECOIN "balanceOf(address)(uint256)" $TEST_USER --rpc-url http://localhost:8545)
echo "   Test user USDT balance: $(echo "scale=2; $USD_BALANCE / 1000000000000000000" | bc) USDT"

# 2. Setup test user compliance in UserRegistry
echo ""
echo "2️⃣  Setting up test user compliance..."
RISK_SCORE=50  # Below max of 83, so compliant
ATTESTATION_HASH="0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"

cast send $USER_REGISTRY "updateUser(address,uint8,bytes32,bool)" \
    $TEST_USER $RISK_SCORE $ATTESTATION_HASH true \
    --rpc-url http://localhost:8545 --private-key $DEPLOYER_KEY > /dev/null 2>&1

IS_COMPLIANT=$(cast call $USER_REGISTRY "isCompliant(address)(bool)" $TEST_USER --rpc-url http://localhost:8545)
echo "   Test user compliant: $IS_COMPLIANT"

# 3. Approve MintEscrow to spend test user's USDT
echo ""
echo "3️⃣  Approving MintEscrow to spend USDT..."
APPROVE_AMOUNT="1000000000000000000"  # 1 USDT
cast send $USD_STABLECOIN "approve(address,uint256)" $MINT_ESCROW $APPROVE_AMOUNT \
    --rpc-url http://localhost:8545 --private-key $TEST_USER_KEY > /dev/null 2>&1
echo "   Approved MintEscrow for 1 USDT"

# 4. Submit mint intent via API
echo ""
echo "4️⃣  Submitting mint intent via API..."
TX_REF="MPESA-DEMO-$(date +%s)"
INTENT_RESPONSE=$(node scripts/api-helper.js submit-intent $TEST_USER $APPROVE_AMOUNT $TX_REF 2>&1)
echo "   Transaction ref: $TX_REF"
echo "   API Response: $INTENT_RESPONSE"

sleep 2

# 5. Trigger M-PESA callback
echo ""
echo "5️⃣  Triggering M-PESA callback..."
CALLBACK_RESPONSE=$(node scripts/api-helper.js trigger-callback $TX_REF $TEST_USER $APPROVE_AMOUNT 2>&1)
echo "   Callback Response: $CALLBACK_RESPONSE"

sleep 3

# 6. Verify mint executed on-chain
echo ""
echo "6️⃣  Verifying mint executed on-chain..."
KES_BALANCE=$(cast call $COUNTRY_TOKEN "balanceOf(address)(uint256)" $TEST_USER --rpc-url http://localhost:8545)
echo "   Test user KES balance: $(echo "scale=2; $KES_BALANCE / 1000000000000000000" | bc) KES"

if [ "$KES_BALANCE" = "$APPROVE_AMOUNT" ]; then
    echo "   ✅ Mint successful! User received 1 KES token"
else
    echo "   ⚠️  Unexpected balance. Expected: $APPROVE_AMOUNT, Got: $KES_BALANCE"
fi

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

