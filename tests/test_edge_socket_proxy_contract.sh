#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_contains_text() {
  local text="$1"
  local pattern="$2"
  if ! grep -Fq "$pattern" <<< "$text"; then
    echo "Assertion failed: expected '$pattern'" >&2
    echo "--- text ---" >&2
    printf '%s\n' "$text" >&2
    exit 1
  fi
}

assert_not_contains_text() {
  local text="$1"
  local pattern="$2"
  if grep -Fq "$pattern" <<< "$text"; then
    echo "Assertion failed: did not expect '$pattern'" >&2
    echo "--- text ---" >&2
    printf '%s\n' "$text" >&2
    exit 1
  fi
}

test_edge_socket_proxy_enabled_contract() {
  local traefik_cfg
  local compose_cfg
  local dynamic_cfg

  SOCKET_PROXY_ENABLE="true"
  SOCKET_PROXY_ENDPOINT="http://docker-socket-proxy:2375"
  SOCKET_PROXY_IMAGE="tecnativa/docker-socket-proxy:latest"
  SOCKET_PROXY_IP="172.30.0.4"
  EDGE_NETWORK_NAME="openclaw-edge"
  TRAEFIK_IMAGE="traefik:v3.0"
  CLOUDFLARED_IMAGE="cloudflare/cloudflared:latest"
  TRAEFIK_DASHBOARD_USERS=""
  TRAEFIK_DASHBOARD_HOST="traefik.example.com"
  TUNNEL_UUID="123e4567-e89b-12d3-a456-426614174000"
  APPS_DOMAIN="example.com"
  BOT_NAME="mckay"
  OPENCLAW_GATEWAY_PORT="18789"
  OPENCLAW_EDGE_UPSTREAM_HOST="172.30.0.1"
  TRAEFIK_IP="172.30.0.2"
  CLOUDFLARED_IP="172.30.0.3"

  traefik_cfg="$(edge_render_traefik_config)"
  compose_cfg="$(edge_render_compose)"
  dynamic_cfg="$(edge_render_openclaw_dynamic_config)"

  assert_contains_text "$traefik_cfg" 'endpoint: "tcp://docker-socket-proxy:2375"'
  assert_contains_text "$compose_cfg" "docker-socket-proxy:"
  assert_contains_text "$compose_cfg" "depends_on:"
  assert_contains_text "$compose_cfg" "docker-socket-proxy"
  assert_contains_text "$dynamic_cfg" 'url: http://172.30.0.1:18789'

  local sock_mount_count
  sock_mount_count="$(grep -Fc '/var/run/docker.sock:/var/run/docker.sock:ro' <<< "$compose_cfg")"
  if [[ "$sock_mount_count" != "1" ]]; then
    echo "Assertion failed: expected docker.sock mount count 1, got ${sock_mount_count}" >&2
    exit 1
  fi
}

test_edge_socket_proxy_disabled_contract() {
  local traefik_cfg
  local compose_cfg

  SOCKET_PROXY_ENABLE="false"
  EDGE_NETWORK_NAME="openclaw-edge"
  TRAEFIK_IMAGE="traefik:v3.0"
  CLOUDFLARED_IMAGE="cloudflare/cloudflared:latest"
  TRAEFIK_DASHBOARD_USERS=""
  TRAEFIK_DASHBOARD_HOST="traefik.example.com"
  TUNNEL_UUID="123e4567-e89b-12d3-a456-426614174000"
  APPS_DOMAIN="example.com"
  BOT_NAME="mckay"
  OPENCLAW_GATEWAY_PORT="18789"
  OPENCLAW_EDGE_UPSTREAM_HOST="172.30.0.1"
  TRAEFIK_IP="172.30.0.2"
  CLOUDFLARED_IP="172.30.0.3"

  traefik_cfg="$(edge_render_traefik_config)"
  compose_cfg="$(edge_render_compose)"

  assert_not_contains_text "$traefik_cfg" 'endpoint: "tcp://'
  assert_not_contains_text "$compose_cfg" "docker-socket-proxy:"
  assert_contains_text "$compose_cfg" "/var/run/docker.sock:/var/run/docker.sock:ro"
}

main() {
  # shellcheck source=/dev/null
  source "${ROOT_DIR}/scripts/lib/common.sh"
  # shellcheck source=/dev/null
  source "${ROOT_DIR}/scripts/lib/edge.sh"

  test_edge_socket_proxy_enabled_contract
  test_edge_socket_proxy_disabled_contract
  echo "PASS: test_edge_socket_proxy_contract.sh"
}

main "$@"
