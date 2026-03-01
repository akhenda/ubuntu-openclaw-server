#!/bin/bash
set -euo pipefail

#==============================================================================
# Telegram Pairing Helper Script
#
# Automates Telegram pairing approval for OpenClaw installations.
# Can be used interactively or via CLI arguments.
# Supports both local and remote (SSH) operations.
#
# Usage:
#   ./telegram-pairing-helper.sh                    # Interactive mode
#   ./telegram-pairing-helper.sh --code ABC --user-id 123
#   ./telegram-pairing-helper.sh --ssh-host root@server --ssh-auth password
#==============================================================================

# Configuration
PAIRING_FILE="${PAIRING_FILE:-/root/.openclaw/credentials/telegram-pairing.json}"
DOCKER_COMPOSE_DIR="${DOCKER_COMPOSE_DIR:-/root/openclaw/openclaw}"
SSH_HOST=""
SSH_AUTH=""
SSH_PASSWORD=""
USER_ID=""
PAIRING_CODE=""
AUTO_APPROVE="${AUTO_APPROVE:-yes}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#==============================================================================
# Logging Functions
#==============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

#==============================================================================
# Remote Execution Helper
#==============================================================================

run_remote() {
    local cmd="$1"

    if [ -z "$SSH_HOST" ]; then
        # Local execution
        bash -c "$cmd"
    else
        # Remote execution
        if [ "$SSH_AUTH" = "password" ]; then
            if [ -z "$SSH_PASSWORD" ]; then
                read -s -p "Enter SSH password for $SSH_HOST: " SSH_PASSWORD
                echo ""
            fi
            sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=accept-new "$SSH_HOST" "$cmd"
        else
            ssh -o StrictHostKeyChecking=accept-new "$SSH_HOST" "$cmd"
        fi
    fi
}

#==============================================================================
# Core Functions
#==============================================================================

detect_pairing_requests() {
    log_info "Checking for pending pairing requests..."

    local pairing_data
    pairing_data=$(run_remote "cat $PAIRING_FILE 2>/dev/null" || echo "{}")

    # Extract pending requests
    local requests
    requests=$(echo "$pairing_data" | jq -r '.requests // []' 2>/dev/null || echo "[]")

    local count
    count=$(echo "$requests" | jq 'length' 2>/dev/null || echo "0")

    if [ "$count" -eq 0 ]; then
        log_info "No pending pairing requests found"
        return 1
    fi

    log_success "Found $count pending pairing request(s)"

    # Display pending requests
    echo "$requests" | jq -r '.[] | "  User ID: \(.id)\n  Code: \(.code)\n  Name: \(.meta.firstName // "Unknown")\n  Created: \(.createdAt)\n"'

    echo "$pairing_data"
}

extract_latest_pairing_code() {
    local pairing_data="$1"
    echo "$pairing_data" | jq -r '.requests[-1].code // empty' 2>/dev/null || echo ""
}

extract_latest_user_id() {
    local pairing_data="$1"
    echo "$pairing_data" | jq -r '.requests[-1].id // empty' 2>/dev/null || echo ""
}

approve_pairing() {
    local user_id="$1"
    local code="$2"

    log_info "Approving pairing for user $user_id with code $code..."

    # Create backup
    log_info "Creating backup..."
    run_remote "cp $PAIRING_FILE ${PAIRING_FILE}.backup-\$(date +%Y%m%d-%H%M%S)"

    # Read current pairing data
    local pairing_data
    pairing_data=$(run_remote "cat $PAIRING_FILE")

    # Find the request to approve
    local request
    request=$(echo "$pairing_data" | jq --arg id "$user_id" --arg code "$code" \
        '.requests[] | select(.id == $id and .code == $code)' 2>/dev/null || echo "{}")

    if [ "$request" = "{}" ]; then
        log_error "Pairing request not found for user $user_id with code $code"
        return 1
    fi

    # Add approvedAt timestamp
    local approved_request
    approved_request=$(echo "$request" | jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" \
        '. + {approvedAt: $now}')

    # Remove from requests and add to approved
    local new_pairing_data
    new_pairing_data=$(echo "$pairing_data" | jq --arg id "$user_id" --arg code "$code" \
        --argjson approved "$approved_request" \
        '.requests = (.requests | map(select(.id != $id or .code != $code))) |
         .approved = ((.approved // []) + [$approved])')

    # Write new pairing data
    local temp_file="/tmp/telegram-pairing-$$.json"
    echo "$new_pairing_data" | jq '.' > "$temp_file"

    if [ -z "$SSH_HOST" ]; then
        # Local
        sudo cp "$temp_file" "$PAIRING_FILE"
        sudo chown 1000:1000 "$PAIRING_FILE"
        sudo chmod 600 "$PAIRING_FILE"
    else
        # Remote
        if [ "$SSH_AUTH" = "password" ]; then
            sshpass -p "$SSH_PASSWORD" scp -o StrictHostKeyChecking=accept-new "$temp_file" "$SSH_HOST:$PAIRING_FILE"
        else
            scp -o StrictHostKeyChecking=accept-new "$temp_file" "$SSH_HOST:$PAIRING_FILE"
        fi
        run_remote "chown 1000:1000 $PAIRING_FILE && chmod 600 $PAIRING_FILE"
    fi

    rm -f "$temp_file"

    log_success "Pairing approved successfully"
}

verify_pairing() {
    local user_id="$1"
    local code="$2"

    log_info "Verifying pairing approval..."

    local pairing_data
    pairing_data=$(run_remote "cat $PAIRING_FILE")

    # Check if user is in approved list
    local approved
    approved=$(echo "$pairing_data" | jq --arg id "$user_id" --arg code "$code" \
        '.approved // [] | map(select(.id == $id and .code == $code)) | length' 2>/dev/null || echo "0")

    if [ "$approved" -gt 0 ]; then
        log_success "Pairing verified: user $user_id is approved"
        return 0
    else
        log_error "Pairing verification failed: user $user_id not found in approved list"
        return 1
    fi
}

restart_gateway() {
    log_info "Restarting OpenClaw gateway..."

    run_remote "cd $DOCKER_COMPOSE_DIR && docker compose restart openclaw-gateway" || {
        log_error "Failed to restart gateway"
        return 1
    }

    log_success "Gateway restarted successfully"
    sleep 3  # Give gateway time to start
}

#==============================================================================
# Main Workflow
#==============================================================================

interactive_mode() {
    log_section "Telegram Pairing Helper - Interactive Mode"

    # Detect pending requests
    local pairing_data
    pairing_data=$(detect_pairing_requests) || {
        log_warn "No pending requests. Have the user send a message to the bot first."
        exit 0
    }

    # Auto-extract latest request
    PAIRING_CODE=$(extract_latest_pairing_code "$pairing_data")
    USER_ID=$(extract_latest_user_id "$pairing_data")

    if [ -z "$PAIRING_CODE" ] || [ -z "$USER_ID" ]; then
        log_error "Could not extract pairing information"
        exit 1
    fi

    log_info "Latest pairing request:"
    echo "  User ID: $USER_ID"
    echo "  Code: $PAIRING_CODE"
    echo ""

    # Confirm approval
    if [ "$AUTO_APPROVE" != "yes" ]; then
        read -p "Approve this pairing request? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy] ]]; then
            log_info "Pairing cancelled by user"
            exit 0
        fi
    fi

    # Approve pairing
    approve_pairing "$USER_ID" "$PAIRING_CODE" || exit 1

    # Verify
    verify_pairing "$USER_ID" "$PAIRING_CODE" || exit 1

    # Restart gateway
    restart_gateway || exit 1

    log_section "Pairing Complete"
    log_success "User $USER_ID can now use the Telegram bot!"
    log_info "Have them send another message to test."
}

#==============================================================================
# CLI Argument Parsing
#==============================================================================

show_usage() {
    cat << EOF
Telegram Pairing Helper Script

Usage:
  $0 [OPTIONS]

Options:
  --user-id <id>           User ID to approve
  --code <code>            Pairing code to approve
  --ssh-host <host>        SSH host for remote operation (e.g., root@server)
  --ssh-auth <method>      SSH auth method: password or key (default: key)
  --auto-approve <yes|no>  Auto-approve without confirmation (default: yes)
  --pairing-file <path>    Path to pairing file (default: /root/.openclaw/credentials/telegram-pairing.json)
  --docker-dir <path>      Path to docker-compose directory (default: /root/openclaw/openclaw)
  -h, --help               Show this help message

Examples:
  # Interactive mode (auto-detect pending requests)
  $0

  # Approve specific request
  $0 --user-id 789273209 --code 3HW3XQLL

  # Remote mode with password auth
  $0 --ssh-host root@your-server.com --ssh-auth password

  # Remote mode with specific request
  $0 --ssh-host root@server --user-id 123 --code ABC123
EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --user-id)
                USER_ID="$2"
                shift 2
                ;;
            --code)
                PAIRING_CODE="$2"
                shift 2
                ;;
            --ssh-host)
                SSH_HOST="$2"
                shift 2
                ;;
            --ssh-auth)
                SSH_AUTH="$2"
                shift 2
                ;;
            --auto-approve)
                AUTO_APPROVE="$2"
                shift 2
                ;;
            --pairing-file)
                PAIRING_FILE="$2"
                shift 2
                ;;
            --docker-dir)
                DOCKER_COMPOSE_DIR="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

#==============================================================================
# Main Entry Point
#==============================================================================

main() {
    parse_arguments "$@"

    # Check dependencies
    for cmd in jq; do
        if ! command -v $cmd &> /dev/null; then
            log_error "Required command not found: $cmd"
            log_info "Install with: sudo apt-get install -y $cmd"
            exit 1
        fi
    done

    if [ -n "$SSH_HOST" ] && [ "$SSH_AUTH" = "password" ]; then
        if ! command -v sshpass &> /dev/null; then
            log_error "sshpass not found (required for password auth)"
            log_info "Install with: sudo apt-get install -y sshpass"
            exit 1
        fi
    fi

    # If user_id and code are provided, use them directly
    if [ -n "$USER_ID" ] && [ -n "$PAIRING_CODE" ]; then
        log_section "Telegram Pairing Helper - Direct Mode"
        approve_pairing "$USER_ID" "$PAIRING_CODE" || exit 1
        verify_pairing "$USER_ID" "$PAIRING_CODE" || exit 1
        restart_gateway || exit 1
        log_section "Pairing Complete"
        log_success "User $USER_ID can now use the Telegram bot!"
    else
        # Interactive mode
        interactive_mode
    fi
}

# Run main function
main "$@"
