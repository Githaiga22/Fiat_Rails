#!/bin/bash

# Deploy contracts from inside Docker network
# This bypasses the localhost binding issue

set -e

echo "════════════════════════════════════════════════════════"
echo "       FiatRails - Docker Network Deployment"
echo "════════════════════════════════════════════════════════"
echo ""

# Anvil default accounts
DEPLOYER="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
TEST_USER="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
DEPLOYER_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
TEST_USER_KEY="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"

echo "📝 Deploying contracts via Docker..."
echo ""

# Run forge inside a temporary foundry container on the same network
sudo docker run --rm \
  --network fiatrails_fiatrails \
  -v $(pwd)/contracts:/app/contracts \
  -w /app/contracts \
  ghcr.io/foundry-rs/foundry:latest \
  forge script script/Deploy.s.sol \
    --rpc-url http://anvil:8545 \
    --private-key $DEPLOYER_KEY \
    --broadcast

echo ""
echo "✅ Contracts deployed!"
echo ""

# Extract deployed addresses from broadcast folder
cd contracts
BROADCAST_FILE=$(ls -t broadcast/Deploy.s.sol/31382/run-latest.json 2>/dev/null | head -1)

if [ -f "$BROADCAST_FILE" ]; then
    USD_STABLECOIN=$(jq -r '.transactions[] | select(.contractName == "USDStablecoin") | .contractAddress' "$BROADCAST_FILE")
    COUNTRY_TOKEN=$(jq -r '.transactions[] | select(.contractName == "CountryToken") | .contractAddress' "$BROADCAST_FILE")
    USER_REGISTRY=$(jq -r '.transactions[] | select(.contractName == "UserRegistry") | .contractAddress' "$BROADCAST_FILE")
    COMPLIANCE_MANAGER=$(jq -r '.transactions[] | select(.contractName == "ERC1967Proxy") | .contractAddress' "$BROADCAST_FILE" | head -1)
    MINT_ESCROW=$(jq -r '.transactions[] | select(.contractName == "MintEscrow") | .contractAddress' "$BROADCAST_FILE")

    echo "📋 Deployed addresses:"
    echo "  USDStablecoin: $USD_STABLECOIN"
    echo "  CountryToken: $COUNTRY_TOKEN"
    echo "  UserRegistry: $USER_REGISTRY"
    echo "  ComplianceManager: $COMPLIANCE_MANAGER"
    echo "  MintEscrow: $MINT_ESCROW"
    echo ""

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
  "chainId": 31382,
  "rpcUrl": "http://localhost:8545",
  "timestamp": $(date +%s)
}
EOF

    echo "✅ deployments.json created"
    echo ""

    # Now setup test data using cast from host (should work now)
    echo "🧪 Setting up test data..."

    # 1. Pre-mint USD tokens
    echo "1️⃣  Pre-minting 10,000 USDT to test user..."
    MINT_AMOUNT="10000000000000000000000"
    cast send $USD_STABLECOIN "mint(address,uint256)" $TEST_USER $MINT_AMOUNT \
        --rpc-url http://localhost:8545 --private-key $DEPLOYER_KEY > /dev/null 2>&1

    USD_BALANCE=$(cast call $USD_STABLECOIN "balanceOf(address)(uint256)" $TEST_USER --rpc-url http://localhost:8545)
    echo "   ✅ Test user USDT balance: $(echo "scale=2; $USD_BALANCE / 1000000000000000000" | bc) USDT"

    # 2. Setup compliance
    echo ""
    echo "2️⃣  Setting up test user compliance..."
    RISK_SCORE=50
    ATTESTATION_HASH="0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"

    cast send $USER_REGISTRY "updateUser(address,uint8,bytes32,bool)" \
        $TEST_USER $RISK_SCORE $ATTESTATION_HASH true \
        --rpc-url http://localhost:8545 --private-key $DEPLOYER_KEY > /dev/null 2>&1

    IS_COMPLIANT=$(cast call $USER_REGISTRY "isCompliant(address)(bool)" $TEST_USER --rpc-url http://localhost:8545)
    echo "   ✅ Test user compliant: $IS_COMPLIANT"

    echo ""
    echo "════════════════════════════════════════════════════════"
    echo "                DEPLOYMENT COMPLETE"
    echo "════════════════════════════════════════════════════════"
    echo ""
    echo "Next steps:"
    echo "  - Test API: curl http://localhost:3000/health"
    echo "  - View Grafana: http://localhost:3001"
    echo "  - Run retry test: ./scripts/test-retry-dlq.sh"
    echo ""
else
    echo "❌ Failed to find deployment broadcast file"
    cd ..
    exit 1
fi
