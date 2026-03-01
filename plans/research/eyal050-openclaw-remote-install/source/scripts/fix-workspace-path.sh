#!/bin/bash
set -e

# Fix Workspace Path Configuration
# This script fixes the common issue where the workspace path in openclaw.json
# is set to the host path instead of the container path.

REMOTE_HOST="${REMOTE_HOST:-}"
SSH_PASSWORD="${SSH_PASSWORD:-}"

if [ -z "$REMOTE_HOST" ]; then
    echo "Error: REMOTE_HOST is not set."
    echo "Usage: REMOTE_HOST=root@your-server.com ./fix-workspace-path.sh"
    echo "       REMOTE_HOST=root@your-server.com SSH_PASSWORD=yourpass ./fix-workspace-path.sh"
    exit 1
fi
CONFIG_FILE="/root/.openclaw/openclaw.json"
DOCKER_DIR="/root/openclaw/openclaw"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "========================================"
echo "  Fix OpenClaw Workspace Path"
echo "========================================"
echo ""

run_remote() {
    if [ -n "$SSH_PASSWORD" ]; then
        export SSHPASS="$SSH_PASSWORD"
        sshpass -e ssh -o StrictHostKeyChecking=accept-new "$REMOTE_HOST" "$@"
    else
        ssh -o StrictHostKeyChecking=accept-new "$REMOTE_HOST" "$@"
    fi
}

# Check current workspace path
echo -e "${BLUE}[1/3]${NC} Checking current workspace path..."
CURRENT_PATH=$(run_remote "cat $CONFIG_FILE" | python3 -c "
import sys, json
try:
    config = json.load(sys.stdin)
    print(config.get('agents', {}).get('defaults', {}).get('workspace', ''))
except:
    pass
" 2>/dev/null || echo "")

if [ -z "$CURRENT_PATH" ]; then
    echo -e "  ${RED}✗${NC} Could not read workspace path from config"
    exit 1
fi

echo -e "     Current path: ${CURRENT_PATH}"

if [ "$CURRENT_PATH" = "/home/node/.openclaw/workspace" ]; then
    echo -e "  ${GREEN}✓${NC} Workspace path is already correct!"
    exit 0
fi

echo -e "  ${YELLOW}⚠${NC}  Workspace path needs fixing"
echo -e "     Expected: /home/node/.openclaw/workspace"
echo ""

# Fix the configuration
echo -e "${BLUE}[2/3]${NC} Fixing workspace path in configuration..."

# Download config
if [ -n "$SSH_PASSWORD" ]; then
    export SSHPASS="$SSH_PASSWORD"
    sshpass -e scp -o StrictHostKeyChecking=accept-new "$REMOTE_HOST:$CONFIG_FILE" /tmp/openclaw-config.json
else
    scp -o StrictHostKeyChecking=accept-new "$REMOTE_HOST:$CONFIG_FILE" /tmp/openclaw-config.json
fi

# Fix workspace path
python3 << 'EOF'
import json

with open('/tmp/openclaw-config.json', 'r') as f:
    config = json.load(f)

# Fix the workspace path to container path
if 'agents' in config and 'defaults' in config['agents']:
    config['agents']['defaults']['workspace'] = '/home/node/.openclaw/workspace'

with open('/tmp/openclaw-config-fixed.json', 'w') as f:
    json.dump(config, f, indent=2)

print("✓ Fixed workspace path in config")
EOF

# Upload fixed config
if [ -n "$SSH_PASSWORD" ]; then
    export SSHPASS="$SSH_PASSWORD"
    sshpass -e scp -o StrictHostKeyChecking=accept-new /tmp/openclaw-config-fixed.json "$REMOTE_HOST:$CONFIG_FILE"
else
    scp -o StrictHostKeyChecking=accept-new /tmp/openclaw-config-fixed.json "$REMOTE_HOST:$CONFIG_FILE"
fi

echo -e "  ${GREEN}✓${NC} Configuration updated"
echo ""

# Restart gateway
echo -e "${BLUE}[3/3]${NC} Restarting gateway to apply changes..."
run_remote "cd $DOCKER_DIR && docker compose restart openclaw-gateway" > /dev/null 2>&1

sleep 5

echo -e "  ${GREEN}✓${NC} Gateway restarted"
echo ""

# Verify fix
echo "Verifying fix..."
NEW_PATH=$(run_remote "cat $CONFIG_FILE" | python3 -c "
import sys, json
try:
    config = json.load(sys.stdin)
    print(config.get('agents', {}).get('defaults', {}).get('workspace', ''))
except:
    pass
" 2>/dev/null || echo "")

if [ "$NEW_PATH" = "/home/node/.openclaw/workspace" ]; then
    echo ""
    echo "=========================================="
    echo -e "${GREEN}✓ WORKSPACE PATH FIXED!${NC}"
    echo "=========================================="
    echo ""
    echo "The workspace path is now correct."
    echo "Your Telegram bot should work properly now."
    echo ""
    exit 0
else
    echo ""
    echo -e "${RED}✗ Fix verification failed${NC}"
    echo "Current path: $NEW_PATH"
    exit 1
fi
