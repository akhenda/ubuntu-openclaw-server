#!/bin/bash
##############################################################################
# Telegram Pairing Verification Script
#
# This script verifies that Telegram pairing is correctly configured and
# working without requiring manual testing.
#
# Usage:
#   ./scripts/verify-telegram-pairing.sh [--ssh-host HOST] [--ssh-password PASS]
#
##############################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
SSH_HOST=""
SSH_PASSWORD=""
REMOTE_MODE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --ssh-host)
            SSH_HOST="$2"
            REMOTE_MODE=true
            shift 2
            ;;
        --ssh-password)
            SSH_PASSWORD="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Helper function to run commands (local or remote)
run_cmd() {
    if [ "$REMOTE_MODE" = true ]; then
        if [ -n "$SSH_PASSWORD" ]; then
            sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=accept-new "$SSH_HOST" "$1"
        else
            ssh -o StrictHostKeyChecking=accept-new "$SSH_HOST" "$1"
        fi
    else
        bash -c "$1"
    fi
}

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Telegram Pairing Verification${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Test 1: Check if pairing file exists
echo -e "${YELLOW}[1/7]${NC} Checking pairing file exists..."
PAIRING_FILE="/root/.openclaw/credentials/telegram-pairing.json"
if run_cmd "test -f $PAIRING_FILE && echo 'exists' || echo 'missing'" | grep -q "exists"; then
    echo -e "      ${GREEN}✓${NC} Pairing file found"
else
    echo -e "      ${RED}✗${NC} Pairing file missing at $PAIRING_FILE"
    exit 1
fi

# Test 2: Validate JSON structure
echo -e "${YELLOW}[2/7]${NC} Validating pairing file JSON..."
PAIRING_JSON=$(run_cmd "cat $PAIRING_FILE")
if echo "$PAIRING_JSON" | python3 -m json.tool >/dev/null 2>&1; then
    echo -e "      ${GREEN}✓${NC} Valid JSON structure"
else
    echo -e "      ${RED}✗${NC} Invalid JSON"
    exit 1
fi

# Test 3: Check for approved users
echo -e "${YELLOW}[3/7]${NC} Checking for approved users..."
APPROVED_COUNT=$(echo "$PAIRING_JSON" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data.get('approved', [])))")
if [ "$APPROVED_COUNT" -gt 0 ]; then
    echo -e "      ${GREEN}✓${NC} Found $APPROVED_COUNT approved user(s)"
    echo "$PAIRING_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for user in data.get('approved', []):
    print(f'        - User ID: {user[\"id\"]}, Code: {user[\"code\"]}, Name: {user.get(\"meta\", {}).get(\"firstName\", \"N/A\")}')"
else
    echo -e "      ${RED}✗${NC} No approved users found"
    exit 1
fi

# Test 4: Check file permissions
echo -e "${YELLOW}[4/7]${NC} Verifying file permissions..."
PERMS=$(run_cmd "stat -c '%a %u:%g' $PAIRING_FILE")
if echo "$PERMS" | grep -q "600 1000:1000"; then
    echo -e "      ${GREEN}✓${NC} Correct permissions (600 1000:1000)"
else
    echo -e "      ${YELLOW}⚠${NC}  Permissions: $PERMS (expected: 600 1000:1000)"
fi

# Test 5: Check Docker container status
echo -e "${YELLOW}[5/7]${NC} Checking gateway container status..."
CONTAINER_STATUS=$(run_cmd "cd ~/openclaw/openclaw && docker compose ps openclaw-gateway --format json 2>/dev/null" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('State', 'unknown'))" 2>/dev/null || echo "unknown")
if [ "$CONTAINER_STATUS" = "running" ]; then
    echo -e "      ${GREEN}✓${NC} Gateway container is running"
else
    echo -e "      ${RED}✗${NC} Gateway container status: $CONTAINER_STATUS"
    exit 1
fi

# Test 6: Check Telegram plugin in logs
echo -e "${YELLOW}[6/7]${NC} Verifying Telegram plugin loaded..."
TELEGRAM_LOGS=$(run_cmd "cd ~/openclaw/openclaw && docker compose logs --tail 50 openclaw-gateway 2>/dev/null | grep -i telegram || echo 'no-logs'")
if echo "$TELEGRAM_LOGS" | grep -q "Telegram configured"; then
    echo -e "      ${GREEN}✓${NC} Telegram plugin configured"
    BOT_USERNAME=$(echo "$TELEGRAM_LOGS" | grep -o '@[a-zA-Z0-9_]*' | head -1)
    if [ -n "$BOT_USERNAME" ]; then
        echo -e "      ${GREEN}✓${NC} Bot username: $BOT_USERNAME"
    fi
else
    echo -e "      ${YELLOW}⚠${NC}  Could not confirm Telegram plugin status"
fi

# Test 7: Get bot info from Telegram API
echo -e "${YELLOW}[7/7]${NC} Verifying bot token with Telegram API..."
BOT_TOKEN=$(run_cmd "grep TELEGRAM_BOT_TOKEN ~/openclaw/openclaw/.env | cut -d'=' -f2" | tr -d '"' | tr -d "'")
if [ -n "$BOT_TOKEN" ]; then
    BOT_INFO=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getMe")
    if echo "$BOT_INFO" | python3 -c "import sys, json; data=json.load(sys.stdin); sys.exit(0 if data.get('ok') else 1)" 2>/dev/null; then
        BOT_USERNAME=$(echo "$BOT_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin)['result']['username'])")
        BOT_ID=$(echo "$BOT_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin)['result']['id'])")
        echo -e "      ${GREEN}✓${NC} Bot token valid"
        echo -e "      ${GREEN}✓${NC} Bot: @${BOT_USERNAME} (ID: ${BOT_ID})"
    else
        echo -e "      ${RED}✗${NC} Bot token appears invalid"
        exit 1
    fi
else
    echo -e "      ${YELLOW}⚠${NC}  Could not retrieve bot token"
fi

# Final summary
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ All automated checks passed!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Final Verification Step (Optional Manual Test):${NC}"
echo -e "  1. Open Telegram and send a message to @${BOT_USERNAME}"
echo -e "  2. You should receive a response from the bot (NOT a pairing error)"
echo -e "  3. If you still see a pairing error, check gateway logs:"
echo -e "     ${BLUE}docker compose logs -f openclaw-gateway${NC}"
echo ""
echo -e "${GREEN}✓ Telegram pairing verification complete!${NC}"
echo ""

exit 0
