#!/bin/bash
################################################################################
# OpenClaw Telegram Pairing Fix Script
# Version: 1.0.0
#
# This script automatically detects and approves pending Telegram pairing requests.
# It can be run locally or remotely via SSH.
#
# Usage:
#   Local:  ./fix-telegram-pairing.sh
#   Remote: ./fix-telegram-pairing.sh --ssh root@your-server.com
#
################################################################################

set -euo pipefail

# Default configuration
PAIRING_FILE="${HOME}/.openclaw/credentials/telegram-pairing.json"
DOCKER_DIR="${HOME}/openclaw/openclaw"
SSH_HOST=""
SSH_PASSWORD=""
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_section() {
    echo ""
    echo "========================================================================"
    echo "$*"
    echo "========================================================================"
}

# Display usage information
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Automatically detect and approve pending Telegram pairing requests.

Options:
    --pairing-file PATH     Path to telegram-pairing.json (default: ~/.openclaw/credentials/telegram-pairing.json)
    --docker-dir PATH       Path to docker compose directory (default: ~/openclaw/openclaw)
    --ssh HOST              SSH to remote host (e.g., root@your-server.com)
    --ssh-password PASS     SSH password (prompted if not provided)
    --verbose               Enable verbose output
    -h, --help              Show this help message

Examples:
    # Fix pairing locally
    $0

    # Fix pairing on remote server with password prompt
    $0 --ssh root@your-server.com

    # Fix pairing on remote server with password
    $0 --ssh root@your-server.com --ssh-password 'mypassword'

    # Custom pairing file location
    $0 --pairing-file /custom/path/telegram-pairing.json

EOF
    exit 0
}

# Parse command-line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --pairing-file)
                PAIRING_FILE="$2"
                shift 2
                ;;
            --docker-dir)
                DOCKER_DIR="$2"
                shift 2
                ;;
            --ssh)
                SSH_HOST="$2"
                shift 2
                ;;
            --ssh-password)
                SSH_PASSWORD="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done
}

# Execute command locally or remotely
exec_cmd() {
    local cmd="$1"

    if [ -n "$SSH_HOST" ]; then
        if [ -n "$SSH_PASSWORD" ]; then
            sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=accept-new "$SSH_HOST" "$cmd"
        else
            ssh -o StrictHostKeyChecking=accept-new "$SSH_HOST" "$cmd"
        fi
    else
        bash -c "$cmd"
    fi
}

# Read file locally or remotely
read_file() {
    local file="$1"

    if [ -n "$SSH_HOST" ]; then
        if [ -n "$SSH_PASSWORD" ]; then
            sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=accept-new "$SSH_HOST" "cat $file" 2>/dev/null
        else
            ssh -o StrictHostKeyChecking=accept-new "$SSH_HOST" "cat $file" 2>/dev/null
        fi
    else
        cat "$file" 2>/dev/null
    fi
}

# Check if pairing file exists
check_pairing_file() {
    log_section "Step 1: Checking Pairing File"

    if ! read_file "$PAIRING_FILE" &>/dev/null; then
        log_error "Pairing file not found: $PAIRING_FILE"
        log_info "Make sure OpenClaw is installed and a Telegram bot is configured"
        return 1
    fi

    log_success "Pairing file exists: $PAIRING_FILE"
    return 0
}

# Detect pending pairing requests
detect_pending_requests() {
    log_section "Step 2: Detecting Pending Requests"

    local pairing_data=$(read_file "$PAIRING_FILE")

    if ! echo "$pairing_data" | jq . &>/dev/null; then
        log_error "Pairing file is not valid JSON"
        return 1
    fi

    local pending_count=$(echo "$pairing_data" | jq '.requests | length' 2>/dev/null || echo "0")

    if [ "$pending_count" -eq 0 ]; then
        log_warn "No pending pairing requests found"
        log_info "Send a message to your Telegram bot to generate a pairing request"
        return 1
    fi

    log_success "Found $pending_count pending pairing request(s):"

    # Display pending requests
    echo "$pairing_data" | jq -r '.requests[] | "  - User ID: \(.id), Code: \(.code), Name: \(.meta.firstName // "Unknown")"' 2>/dev/null || true

    return 0
}

# Approve all pending requests
approve_pending_requests() {
    log_section "Step 3: Approving Pending Requests"

    # Create Python approval script (OpenClaw uses separate allowFrom file)
    local approve_script=$(cat <<'PYTHON_EOF'
import json
import sys
import os

pairing_file = sys.argv[1]
credentials_dir = os.path.dirname(pairing_file)

# Backup original pairing file
backup_file = pairing_file + ".backup"
with open(pairing_file, "r") as f:
    pairing_data = json.load(f)
with open(backup_file, "w") as f:
    json.dump(pairing_data, f, indent=2)

requests = pairing_data.get("requests", [])
if not requests:
    print("No pending requests to approve")
    sys.exit(0)

# Extract user IDs from requests
approved_ids = []
for request in requests:
    user_id = request.get("id")
    code = request.get("code")
    account_id = request.get("meta", {}).get("accountId", "default")

    if user_id:
        approved_ids.append(user_id)
        print(f"✓ Approved user {user_id} with code {code}")

# OpenClaw pairing uses separate allowFrom file
allowfrom_file = os.path.join(credentials_dir, "telegram-default-allowFrom.json")

# Read or create allowFrom file
if os.path.exists(allowfrom_file):
    with open(allowfrom_file, "r") as f:
        allowfrom_data = json.load(f)
else:
    allowfrom_data = {"version": 1, "allowFrom": []}

# Add user IDs to allowFrom
existing = set(allowfrom_data.get("allowFrom", []))
for user_id in approved_ids:
    if user_id not in existing:
        allowfrom_data["allowFrom"].append(user_id)

# Write allowFrom file
with open(allowfrom_file, "w") as f:
    json.dump(allowfrom_data, f, indent=2)

# Clear pending requests
pairing_data["requests"] = []
with open(pairing_file, "w") as f:
    json.dump(pairing_data, f, indent=2)

print(f"\n✓ Successfully approved {len(approved_ids)} pairing request(s)")
print(f"✓ Created/updated {allowfrom_file}")
print(f"✓ Backup saved to {backup_file}")
PYTHON_EOF
)

    # Execute approval
    if [ -n "$SSH_HOST" ]; then
        # Remote execution
        log_info "Executing approval on remote host..."

        local remote_script="/tmp/openclaw_approve_pairing_$$.py"

        # Create script on remote
        exec_cmd "cat > $remote_script <<'EOF'
$approve_script
EOF"

        # Execute script
        exec_cmd "python3 $remote_script $PAIRING_FILE"

        # Cleanup
        exec_cmd "rm -f $remote_script"
    else
        # Local execution
        log_info "Executing approval locally..."

        local local_script="/tmp/openclaw_approve_pairing_$$.py"
        echo "$approve_script" > "$local_script"

        python3 "$local_script" "$PAIRING_FILE"

        rm -f "$local_script"
    fi

    # CRITICAL: Set correct ownership for container user (uid:gid 1000:1000)
    log_info "Setting correct file ownership..."
    exec_cmd "chown 1000:1000 $PAIRING_FILE && chmod 600 $PAIRING_FILE"

    log_success "Pairing requests approved successfully!"
    return 0
}

# Stop gateway
stop_gateway() {
    log_section "Step 3A: Stopping Gateway"

    log_info "Stopping OpenClaw gateway to modify pairing file..."

    if exec_cmd "cd $DOCKER_DIR && docker compose stop openclaw-gateway"; then
        log_success "Gateway stopped successfully"
        return 0
    else
        log_error "Failed to stop gateway"
        return 1
    fi
}

# Start gateway
start_gateway() {
    log_section "Step 4: Starting Gateway"

    log_info "Starting OpenClaw gateway with approved pairing..."

    if exec_cmd "cd $DOCKER_DIR && docker compose start openclaw-gateway"; then
        log_success "Gateway started successfully"
        log_info "Waiting 5 seconds for gateway to initialize..."
        sleep 5
        return 0
    else
        log_error "Failed to start gateway"
        log_warn "You may need to start manually:"
        log_warn "  cd $DOCKER_DIR && docker compose start openclaw-gateway"
        return 1
    fi
}

# Verify pairing worked
verify_pairing() {
    log_section "Step 5: Verification"

    local pairing_data=$(read_file "$PAIRING_FILE")

    local approved_count=$(echo "$pairing_data" | jq '.approved | length' 2>/dev/null || echo "0")
    local pending_count=$(echo "$pairing_data" | jq '.requests | length' 2>/dev/null || echo "0")

    log_info "Pairing status:"
    echo "  - Approved users: $approved_count"
    echo "  - Pending requests: $pending_count"

    if [ "$approved_count" -gt 0 ]; then
        log_success "Telegram pairing is configured correctly!"
        log_info "Approved users:"
        echo "$pairing_data" | jq -r '.approved[] | "  - User ID: \(.id), Code: \(.code), Name: \(.meta.firstName // "Unknown")"' 2>/dev/null || true
        return 0
    else
        log_warn "No approved users found"
        return 1
    fi
}

# Main execution
main() {
    log_section "OpenClaw Telegram Pairing Fix"

    parse_args "$@"

    # Check for required tools
    if ! command -v jq &> /dev/null; then
        log_error "jq is required but not installed"
        log_info "Install with: sudo apt-get install -y jq"
        exit 1
    fi

    if [ -n "$SSH_HOST" ]; then
        if [ -z "$SSH_PASSWORD" ] && ! command -v ssh &> /dev/null; then
            log_error "SSH is required but not available"
            exit 1
        fi

        if [ -n "$SSH_PASSWORD" ] && ! command -v sshpass &> /dev/null; then
            log_error "sshpass is required for password authentication"
            log_info "Install with: sudo apt-get install -y sshpass"
            exit 1
        fi

        log_info "Operating on remote host: $SSH_HOST"
    else
        log_info "Operating locally"
    fi

    # Execute fix workflow
    if ! check_pairing_file; then
        exit 1
    fi

    if ! detect_pending_requests; then
        exit 0  # No pending requests is not an error
    fi

    # CRITICAL: Stop gateway before modifying pairing file
    if ! stop_gateway; then
        log_error "Cannot proceed without stopping gateway first"
        exit 1
    fi

    if ! approve_pending_requests; then
        log_error "Approval failed, restarting gateway..."
        start_gateway
        exit 1
    fi

    if ! start_gateway; then
        log_warn "Gateway start failed, but pairing was approved"
        log_info "Try starting manually: cd $DOCKER_DIR && docker compose start openclaw-gateway"
    fi

    verify_pairing

    log_section "Fix Complete!"
    log_success "Your Telegram bot should now be working"
    log_info "Test by sending a message to your bot"
}

# Run main function
main "$@"
