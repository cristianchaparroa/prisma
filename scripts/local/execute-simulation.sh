#!/bin/bash
# 🚀 UNISWAP V4 YIELD MAXIMIZER SIMULATION EXECUTION
# Executes simulation on existing infrastructure
# Prerequisites: Infrastructure must be running (use run-infra.sh first)
# Usage: ./execute-simulation.sh

set -e

# Color codes for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored headers
print_header() {
    echo -e "\n${BLUE}======================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}======================================${NC}\n"
}

print_step() {
    echo -e "${PURPLE}📍 $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_header "🚀 UNISWAP V4 YIELD MAXIMIZER SIMULATION EXECUTION"

START_TIME=$(date +%s)

# Check if infrastructure is running and environment exists
if [ ! -f ".env" ]; then
    print_error "Environment file .env not found!"
    echo "Please run run-infra.sh first to set up the infrastructure."
    exit 1
fi

# Source the environment
source .env

# Verify Anvil is running
print_step "Verifying infrastructure is running..."
if ! cast block-number --rpc-url http://localhost:8545 >/dev/null 2>&1; then
    print_error "Anvil is not running or not accessible!"
    echo "Please run run-infra.sh first to start the infrastructure."
    exit 1
fi

LATEST_BLOCK=$(cast block-number --rpc-url http://localhost:8545)
print_success "Infrastructure verified at block: $LATEST_BLOCK"

print_header "PHASE 4: SIMULATION EXECUTION"

print_step "Step 4.1: Running user simulation..."
#forge script script/local/simulation/08_SimulateUsers.s.sol \
#    --rpc-url http://localhost:8545 \
#    --private-key $ANVIL_PRIVATE_KEY \
#    --broadcast \
#    --skip-simulation > user_simulation.log 2>&1
./scripts/local/08-simulate-users.sh

if [ $? -eq 0 ]; then
    print_success "User simulation completed"
else
    print_warning "User simulation had issues (check user_simulation.log)"
fi

print_step "Step 4.2: Running trading simulation..."
forge script script/local/simulation/09_Simulation.s.sol \
    --rpc-url http://localhost:8545 \
    --private-key $ANVIL_PRIVATE_KEY \
    --broadcast \
    --skip-simulation > trading_simulation.log 2>&1

if [ $? -eq 0 ]; then
    print_success "Trading simulation completed"
else
    print_warning "Trading simulation had issues (check trading_simulation.log)"
fi
