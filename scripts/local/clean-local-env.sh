#!/bin/bash

# Cleanup script for Anvil development environment

# Change to project root directory
cd "$(dirname "$0")/../.."

echo "🧹 Cleaning up Anvil environment..."
echo "📂 Working directory: $(pwd)"

# Kill anvil process if running
if [ -f .env ]; then
    source .env
    if [ ! -z "$ANVIL_PID" ]; then
        echo "🔪 Stopping Anvil (PID: $ANVIL_PID)..."
        kill $ANVIL_PID 2>/dev/null || true
    fi
fi

# Kill any anvil processes
pkill -f anvil || true

# Clean up files
echo "🗑️  Removing generated files..."
rm -f anvil_output.log
rm -f accounts.json
rm -f .env

# Clean up deployment files
rm -rf deployments/*.env
rm -rf broadcast/
rm -rf cache/

echo "✅ Cleanup complete!"
echo "🚀 Run ./scripts/local/run-local-env.sh to start fresh"
