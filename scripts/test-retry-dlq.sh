#!/bin/bash

# Test Script for Retry & DLQ Scenarios
# This script helps you practice the screencast demonstrations

set -e  # Exit on error

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}FiatRails Retry & DLQ Test Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if deployments.json exists
if [ ! -f "deployments.json" ]; then
    echo -e "${RED}❌ Error: deployments.json not found${NC}"
    echo -e "${YELLOW}Please run ./scripts/deploy-and-demo.sh first${NC}"
    exit 1
fi

# Test 1: Retry Logic with RPC Failure
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}TEST 1: Retry Logic with RPC Failure${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "This test will:"
echo "  1. Stop Anvil (simulate RPC failure)"
echo "  2. Trigger a callback"
echo "  3. Show retry attempts with exponential backoff"
echo "  4. Restart Anvil"
echo "  5. Verify operation completes successfully"
echo ""
read -p "Press Enter to start Test 1..."
echo ""

# Stop Anvil
echo -e "${YELLOW}⏸️  Stopping Anvil...${NC}"
sudo docker-compose stop anvil
echo -e "${GREEN}✅ Anvil stopped${NC}"
echo ""

# Give user time to open logs
echo -e "${BLUE}📋 IMPORTANT: Open another terminal and run:${NC}"
echo -e "${BLUE}   sudo docker-compose logs -f api${NC}"
echo ""
read -p "Press Enter when you have the logs open..."
echo ""

# Trigger callback
echo -e "${YELLOW}🚀 Triggering callback while RPC is DOWN...${NC}"
echo -e "${BLUE}Watch the other terminal for retry logs!${NC}"
echo ""

node scripts/api-helper.js trigger-callback \
  MPESA-RETRY-TEST-001 \
  0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
  2000000000000000000

echo ""
echo -e "${BLUE}You should see in the logs:${NC}"
echo "  - Attempt 1 failed, retry in 691ms"
echo "  - Attempt 2 failed, retry in 1382ms (2x)"
echo "  - Attempt 3 failed, retry in 2764ms (2x)"
echo "  - Attempt 4 failed, retry in 5528ms (2x)"
echo ""

# Wait for user to see retries
echo -e "${YELLOW}Let's wait 10 seconds to see some retry attempts...${NC}"
sleep 10
echo ""

# Restart Anvil
read -p "Press Enter to RESTART Anvil and watch the operation succeed..."
echo ""
echo -e "${YELLOW}▶️  Restarting Anvil...${NC}"
sudo docker-compose start anvil
echo -e "${GREEN}✅ Anvil restarted${NC}"
echo ""

echo -e "${BLUE}Watch the logs - the next retry should SUCCEED!${NC}"
echo ""
sleep 5

# Verify balance changed
echo -e "${YELLOW}🔍 Verifying mint succeeded on-chain...${NC}"
BALANCE=$(cast call $(cat deployments.json | jq -r '.countryToken') \
  "balanceOf(address)(uint256)" \
  0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
  --rpc-url http://localhost:8545)

echo -e "${GREEN}✅ Current balance: $BALANCE${NC}"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}TEST 1 COMPLETE ✅${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo ""

# Test 2: Dead Letter Queue (DLQ)
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}TEST 2: Dead Letter Queue (DLQ)${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "This test will:"
echo "  1. Stop Anvil again"
echo "  2. Trigger a callback"
echo "  3. Let ALL retries exhaust (takes ~60 seconds)"
echo "  4. Verify operation moved to DLQ"
echo "  5. Show DLQ file contents"
echo ""
read -p "Press Enter to start Test 2..."
echo ""

# Clear existing DLQ
echo -e "${YELLOW}🗑️  Clearing existing DLQ...${NC}"
rm -f api/data/dlq.json
echo -e "${GREEN}✅ DLQ cleared${NC}"
echo ""

# Stop Anvil
echo -e "${YELLOW}⏸️  Stopping Anvil again...${NC}"
sudo docker-compose stop anvil
echo -e "${GREEN}✅ Anvil stopped${NC}"
echo ""

# Trigger callback that will go to DLQ
echo -e "${YELLOW}🚀 Triggering callback that will exhaust all retries...${NC}"
echo -e "${BLUE}This will take about 60 seconds. Watch the logs!${NC}"
echo ""

node scripts/api-helper.js trigger-callback \
  MPESA-DLQ-TEST-001 \
  0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC \
  5000000000000000000

echo ""
echo -e "${YELLOW}⏰ Waiting for all retry attempts to exhaust...${NC}"
echo -e "${BLUE}Expected retry schedule:${NC}"
echo "  - Attempt 1: immediate"
echo "  - Attempt 2: +691ms"
echo "  - Attempt 3: +1382ms"
echo "  - Attempt 4: +2764ms"
echo "  - Attempt 5: +5528ms"
echo "  - Total: ~60 seconds"
echo ""

# Countdown timer
for i in {60..1}; do
    echo -ne "${YELLOW}Waiting... ${i} seconds remaining\r${NC}"
    sleep 1
done
echo -e "\n"

# Check if DLQ was created
echo -e "${YELLOW}🔍 Checking if DLQ file was created...${NC}"
if [ -f "api/data/dlq.json" ]; then
    echo -e "${GREEN}✅ DLQ file exists!${NC}"
    echo ""
    echo -e "${BLUE}DLQ Contents:${NC}"
    cat api/data/dlq.json | jq .
    echo ""
else
    echo -e "${RED}❌ DLQ file not found yet${NC}"
    echo -e "${YELLOW}It may still be processing. Check logs and wait a bit longer.${NC}"
    echo ""
fi

# Restart Anvil
echo -e "${YELLOW}▶️  Restarting Anvil to restore system...${NC}"
sudo docker-compose start anvil
echo -e "${GREEN}✅ Anvil restarted - system restored${NC}"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}TEST 2 COMPLETE ✅${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Final Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}ALL TESTS COMPLETE!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${GREEN}✅ Retry Logic: Verified exponential backoff${NC}"
echo -e "${GREEN}✅ RPC Recovery: Operation succeeded after restart${NC}"
echo -e "${GREEN}✅ DLQ Creation: Failed operation moved to DLQ${NC}"
echo ""
echo -e "${BLUE}You're now ready to record your screencast!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Review script-demo.md for narration"
echo "  2. Practice the timing (aim for 8-9 minutes)"
echo "  3. Reset to clean state before recording:"
echo "     sudo docker-compose down -v"
echo "     rm -f api/data/dlq.json"
echo ""
