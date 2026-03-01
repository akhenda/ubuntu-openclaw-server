#!/bin/bash
set -e

# Approve a Telegram pairing request via the OpenClaw gateway API.
#
# Usage:
#   ./approve-telegram-pairing.sh --gateway-token TOKEN --server-ip 1.2.3.4 --code CK39NZWY
#   ./approve-telegram-pairing.sh --gateway-token TOKEN --server-ip 1.2.3.4 --port 18789 --code CK39NZWY

GATEWAY_TOKEN=""
SERVER_IP=""
PORT="18789"
PAIRING_CODE=""

usage() {
    cat <<EOF
Usage: $0 --gateway-token TOKEN --server-ip IP --code CODE [--port PORT]

Options:
    --gateway-token TOKEN   OpenClaw gateway bearer token
    --server-ip IP          Server IP address or hostname
    --port PORT             Gateway port (default: 18789)
    --code CODE             Pairing code to approve (e.g. CK39NZWY)
    -h, --help              Show this help message

Examples:
    $0 --gateway-token abc123 --server-ip 1.2.3.4 --code CK39NZWY
    $0 --gateway-token abc123 --server-ip myserver.com --port 18789 --code CK39NZWY
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --gateway-token) GATEWAY_TOKEN="$2"; shift 2 ;;
        --server-ip)     SERVER_IP="$2";     shift 2 ;;
        --port)          PORT="$2";          shift 2 ;;
        --code)          PAIRING_CODE="$2";  shift 2 ;;
        -h|--help)       usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

if [ -z "$GATEWAY_TOKEN" ] || [ -z "$SERVER_IP" ] || [ -z "$PAIRING_CODE" ]; then
    echo "Error: --gateway-token, --server-ip, and --code are required."
    echo ""
    usage
fi

echo "Approving Telegram pairing code: $PAIRING_CODE"
echo ""

echo "Attempting to approve pairing via API..."
RESPONSE=$(curl -s -X POST \
    -H "Authorization: Bearer $GATEWAY_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"code\": \"$PAIRING_CODE\", \"approve\": true}" \
    "http://${SERVER_IP}:${PORT}/api/pairing/approve" 2>&1 || echo "failed")

if echo "$RESPONSE" | grep -q "success\|approved"; then
    echo "✓ Pairing approved successfully!"
    echo ""
    echo "Try sending a message to your Telegram bot now."
else
    echo "API approval failed or response unclear."
    echo "Response: $RESPONSE"
    echo ""
    echo "You can approve the pairing manually via the dashboard:"
    echo "  http://${SERVER_IP}:${PORT}/?token=${GATEWAY_TOKEN}"
    echo ""
    echo "Look for the 'Pairing Requests' or 'Telegram' section and approve code: $PAIRING_CODE"
fi
