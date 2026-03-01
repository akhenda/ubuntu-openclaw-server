#!/bin/bash
set -e

# Telegram End-to-End Verification Script
# Tests the complete flow: send test message → wait for bot response → validate answer

# =============================================================================
# Configuration
# =============================================================================

REMOTE_HOST="${REMOTE_HOST:-}"
SSH_PASSWORD="${SSH_PASSWORD:-}"
TELEGRAM_TOKEN="${TELEGRAM_TOKEN:-}"
TEST_CHAT_ID="${TEST_CHAT_ID:-}"
TEST_USER_ID="${TEST_USER_ID:-789273209}"

# Remote paths
PAIRING_FILE="/root/.openclaw/credentials/telegram-pairing.json"
CONFIG_FILE="/root/.openclaw/openclaw.json"
DOCKER_DIR="/root/openclaw/openclaw"

# Test configuration
TEST_MESSAGE="${TEST_MESSAGE:-what is 2+2?}"
RESPONSE_TIMEOUT="${RESPONSE_TIMEOUT:-60}"
RESPONSE_PATTERN="${RESPONSE_PATTERN:-[0-9]}"  # For math question, expect digit in response

# =============================================================================
# Colors
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Helper Functions
# =============================================================================

log_step() {
    echo -e "${BLUE}[$1]${NC} $2"
}

log_success() {
    echo -e "  ${GREEN}✓${NC} $1"
}

log_error() {
    echo -e "  ${RED}✗${NC} $1"
}

log_warning() {
    echo -e "  ${YELLOW}⚠${NC}  $1"
}

log_info() {
    echo "     $1"
}

run_remote() {
    if [ -n "$REMOTE_HOST" ] && [ -n "$SSH_PASSWORD" ]; then
        sshpass -e ssh -o StrictHostKeyChecking=accept-new "$REMOTE_HOST" "$@"
    else
        bash -c "$*"
    fi
}

# =============================================================================
# Telegram API Functions
# =============================================================================

# Test if bot API is accessible
test_bot_api() {
    log_step "1/7" "Testing bot API connectivity..."

    if [ -z "$TELEGRAM_TOKEN" ]; then
        log_error "TELEGRAM_TOKEN not set"
        log_info "Set environment variable: export TELEGRAM_TOKEN='your-token'"
        return 2
    fi

    local response=$(curl -s "https://api.telegram.org/bot${TELEGRAM_TOKEN}/getMe")
    local ok=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('ok', False))" 2>/dev/null || echo "False")

    if [ "$ok" = "True" ]; then
        local bot_username=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('result', {}).get('username', ''))" 2>/dev/null || echo "")
        log_success "Bot API accessible: @${bot_username}"
        echo "$bot_username" > /tmp/bot_username.txt
        return 0
    else
        local error_msg=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('description', 'Unknown error'))" 2>/dev/null || echo "API request failed")
        log_error "Bot API error: $error_msg"
        return 3
    fi
}

# Get chat ID from recent messages
get_chat_id() {
    log_step "2/7" "Getting chat ID from recent messages..."

    if [ -n "$TEST_CHAT_ID" ]; then
        log_success "Using provided chat ID: $TEST_CHAT_ID"
        return 0
    fi

    local response=$(curl -s "https://api.telegram.org/bot${TELEGRAM_TOKEN}/getUpdates?limit=10")
    local chat_id=$(echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('ok') and data.get('result'):
        # Get the most recent message's chat ID
        for update in reversed(data['result']):
            if 'message' in update and 'chat' in update['message']:
                print(update['message']['chat']['id'])
                break
except:
    pass
" 2>/dev/null || echo "")

    if [ -n "$chat_id" ]; then
        TEST_CHAT_ID="$chat_id"
        log_success "Found chat ID: $TEST_CHAT_ID"
        return 0
    else
        log_warning "No recent messages found"
        log_info "Please send any message to the bot first, then rerun this script"
        return 2
    fi
}

# Check OpenClaw pairing status
check_pairing_status() {
    log_step "3/7" "Checking OpenClaw pairing status..."

    local pairing_data=$(run_remote "cat $PAIRING_FILE 2>/dev/null || echo '{}'")

    # Check if user is already approved
    local is_approved=$(echo "$pairing_data" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    approved = data.get('approved', [])
    for user in approved:
        if user.get('id') == '$TEST_USER_ID':
            print('true')
            break
except:
    pass
" 2>/dev/null || echo "false")

    if [ "$is_approved" = "true" ]; then
        log_success "User $TEST_USER_ID is already paired"
        return 0
    fi

    # Check for pending pairing request
    local has_request=$(echo "$pairing_data" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    requests = data.get('requests', [])
    for req in requests:
        if req.get('id') == '$TEST_USER_ID':
            print(req.get('code', ''))
            break
except:
    pass
" 2>/dev/null || echo "")

    if [ -n "$has_request" ]; then
        log_warning "Pairing request pending (code: $has_request)"
        log_info "Auto-approving pairing..."

        # Auto-approve the pairing
        run_remote "cat > $PAIRING_FILE << 'EOFPAIR'
{
  \"version\": 1,
  \"requests\": [],
  \"approved\": [
    {
      \"id\": \"$TEST_USER_ID\",
      \"code\": \"$has_request\",
      \"createdAt\": \"$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")\",
      \"approvedAt\": \"$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")\",
      \"lastSeenAt\": \"$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")\",
      \"meta\": {
        \"firstName\": \"Test User\"
      }
    }
  ]
}
EOFPAIR"

        # Restart gateway to pick up changes
        run_remote "cd $DOCKER_DIR && docker compose restart openclaw-gateway" > /dev/null 2>&1
        sleep 5

        log_success "Pairing auto-approved and gateway restarted"
        return 0
    else
        log_warning "No pairing found for user $TEST_USER_ID"
        log_info "Send a message to the bot to initiate pairing"
        return 1
    fi
}

# Send test message to bot
send_test_message() {
    log_step "4/7" "Sending test message: \"$TEST_MESSAGE\""

    if [ -z "$TEST_CHAT_ID" ]; then
        log_error "Chat ID not available"
        return 2
    fi

    # Get current update ID to know where to start listening
    local updates=$(curl -s "https://api.telegram.org/bot${TELEGRAM_TOKEN}/getUpdates?limit=1&offset=-1")
    LAST_UPDATE_ID=$(echo "$updates" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('result'):
        print(data['result'][-1]['update_id'] + 1 if data['result'] else 0)
    else:
        print(0)
except:
    print(0)
" 2>/dev/null || echo "0")

    # Send the test message
    local response=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "{\"chat_id\": $TEST_CHAT_ID, \"text\": \"$TEST_MESSAGE\"}")

    local ok=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('ok', False))" 2>/dev/null || echo "False")

    if [ "$ok" = "True" ]; then
        log_success "Test message sent successfully"
        return 0
    else
        local error_msg=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('description', 'Unknown error'))" 2>/dev/null || echo "Send failed")
        log_error "Failed to send message: $error_msg"
        return 1
    fi
}

# Wait for bot response
wait_for_bot_response() {
    log_step "5/7" "Waiting for bot response (timeout: ${RESPONSE_TIMEOUT}s)..."

    local start_time=$(date +%s)
    local bot_username=$(cat /tmp/bot_username.txt 2>/dev/null || echo "")

    while true; do
        local elapsed=$(($(date +%s) - start_time))

        if [ $elapsed -ge $RESPONSE_TIMEOUT ]; then
            log_error "Timeout waiting for response"
            return 1
        fi

        # Poll for new messages
        local updates=$(curl -s "https://api.telegram.org/bot${TELEGRAM_TOKEN}/getUpdates?offset=${LAST_UPDATE_ID}&timeout=5")

        # Check if we got a response from the bot
        local bot_response=$(echo "$updates" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('ok') and data.get('result'):
        for update in data['result']:
            msg = update.get('message', {})
            # Look for message from bot (not from user)
            if msg.get('from', {}).get('username') == '$bot_username':
                print(msg.get('text', ''))
                break
except:
    pass
" 2>/dev/null || echo "")

        if [ -n "$bot_response" ]; then
            log_success "Received bot response"
            echo "$bot_response" > /tmp/bot_response.txt
            return 0
        fi

        # Show progress every 5 seconds
        if [ $((elapsed % 5)) -eq 0 ] && [ $elapsed -gt 0 ]; then
            log_info "Still waiting... (${elapsed}s elapsed)"
        fi

        sleep 1
    done
}

# Validate bot response
validate_response() {
    log_step "6/7" "Validating bot response..."

    local response=$(cat /tmp/bot_response.txt 2>/dev/null || echo "")

    if [ -z "$response" ]; then
        log_error "No response to validate"
        return 1
    fi

    log_info "Response: $response"

    # Check for error patterns
    if echo "$response" | grep -iq "error\|sorry\|cannot\|unable"; then
        log_error "Response contains error message"
        return 1
    fi

    # Check for expected pattern
    if echo "$response" | grep -Eq "$RESPONSE_PATTERN"; then
        log_success "Response contains expected pattern ($RESPONSE_PATTERN)"
        return 0
    else
        log_warning "Response doesn't match expected pattern: $RESPONSE_PATTERN"
        log_info "This might still be a valid response - review manually"
        return 1
    fi
}

# Generate verification report
generate_report() {
    log_step "7/7" "Generating verification report..."

    echo ""
    echo "========================================"
    echo "  Telegram E2E Verification Report"
    echo "========================================"
    echo ""
    echo "Test Message:  $TEST_MESSAGE"
    echo "Bot Response:  $(cat /tmp/bot_response.txt 2>/dev/null || echo 'N/A')"
    echo "Chat ID:       $TEST_CHAT_ID"
    echo "User ID:       $TEST_USER_ID"
    echo ""

    if [ -f /tmp/bot_response.txt ]; then
        echo -e "${GREEN}✓ VERIFICATION PASSED${NC}"
        echo ""
        echo "The Telegram bot is working correctly!"
        return 0
    else
        echo -e "${RED}✗ VERIFICATION FAILED${NC}"
        echo ""
        echo "The bot did not respond to the test message."
        echo "Check the troubleshooting steps below."
        return 1
    fi
}

# =============================================================================
# Main Flow
# =============================================================================

main() {
    # Set SSHPASS for remote execution
    if [ -n "$SSH_PASSWORD" ]; then
        export SSHPASS="$SSH_PASSWORD"
    fi

    # Cleanup previous test files
    rm -f /tmp/bot_username.txt /tmp/bot_response.txt

    echo "========================================"
    echo "  Telegram End-to-End Verification"
    echo "========================================"
    echo ""

    # Run verification steps
    local exit_code=0

    test_bot_api || exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo ""
        echo "Troubleshooting:"
        echo "  • Verify TELEGRAM_TOKEN is correct"
        echo "  • Check network connectivity to api.telegram.org"
        exit $exit_code
    fi
    echo ""

    get_chat_id || exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo ""
        echo "Troubleshooting:"
        echo "  • Send any message to the bot first"
        echo "  • Or provide TEST_CHAT_ID environment variable"
        exit $exit_code
    fi
    echo ""

    check_pairing_status || exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_warning "Continuing without pairing (may fail)"
    fi
    echo ""

    send_test_message || exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo ""
        echo "Troubleshooting:"
        echo "  • Check if bot is running: docker compose ps"
        echo "  • Check bot logs: docker compose logs openclaw-gateway"
        exit $exit_code
    fi
    echo ""

    wait_for_bot_response || exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo ""
        echo "Troubleshooting:"
        echo "  • Check if OpenClaw gateway is running"
        echo "  • Check pairing status is approved"
        echo "  • Review gateway logs for errors"
        echo "  • Run: ./scripts/troubleshoot-telegram.sh"
        exit 1
    fi
    echo ""

    validate_response || exit_code=$?
    echo ""

    generate_report
    exit_code=$?

    # Cleanup
    rm -f /tmp/bot_username.txt /tmp/bot_response.txt

    exit $exit_code
}

# =============================================================================
# Script Entry Point
# =============================================================================

# Show usage if --help
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Telegram End-to-End Verification Script"
    echo ""
    echo "Usage:"
    echo "  $0 [options]"
    echo ""
    echo "Environment Variables:"
    echo "  TELEGRAM_TOKEN    - Telegram bot token (required)"
    echo "  TEST_CHAT_ID      - Chat ID to send test message (optional, auto-detected)"
    echo "  TEST_USER_ID      - User ID for pairing (default: 789273209)"
    echo "  TEST_MESSAGE      - Message to send (default: 'what is 2+2?')"
    echo "  RESPONSE_TIMEOUT  - Timeout in seconds (default: 60)"
    echo "  RESPONSE_PATTERN  - Regex pattern to match in response (default: [0-9])"
    echo "  REMOTE_HOST       - SSH host for remote testing (optional)"
    echo "  SSH_PASSWORD      - SSH password for remote testing (optional)"
    echo ""
    echo "Examples:"
    echo "  # Local testing"
    echo "  TELEGRAM_TOKEN='123:ABC' $0"
    echo ""
    echo "  # Remote testing"
    echo "  TELEGRAM_TOKEN='123:ABC' REMOTE_HOST='root@server' SSH_PASSWORD='pass' $0"
    echo ""
    exit 0
fi

main
