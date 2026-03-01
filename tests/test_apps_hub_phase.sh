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

setup_apps_context() {
  EDGE_NETWORK_NAME="openclaw-edge"
  APPS_COMPOSE_FILE="/opt/openclaw/apps/docker-compose.yml"
  APPS_ROOT_DIR="/opt/openclaw/apps"
  APPS_REGISTER_SCRIPT="/opt/openclaw/bin/register_app.py"
  APPS_DEPLOY_SCRIPT="/opt/openclaw/bin/deploy_app.sh"
  DNS_BIN_DIR="/opt/openclaw/bin"
  APPS_VENV_DIR="/opt/openclaw/.venv"
  APPS_DOMAIN="example.com"
  BOT_NAME="cherry"
  HUB_ENABLE="true"
  HUB_AUTOCREATE_ON_FIRST_APP="true"
  HUB_PRIMARY_HOST="hub.example.com"
  HUB_ALIAS_HOST="apps.example.com"
  HUB_STYLE_PROFILE="modern-minimal"
  SOCKET_PROXY_ENDPOINT="http://docker-socket-proxy:2375"
}

test_register_script_contains_homepage_labels_and_reserved_hub() {
  local register_script
  register_script="$(apps_render_register_script)"

  assert_contains_text "$register_script" 'if app_name in {"traefik", RESERVED_BOT_NAME, HUB_SERVICE_NAME}:'
  assert_contains_text "$register_script" '"homepage.group=Apps"'
  assert_contains_text "$register_script" 'f"homepage.name={app_name}"'
  assert_contains_text "$register_script" 'f"homepage.icon={icon_for_app(app_name)}"'
  assert_contains_text "$register_script" 'f"homepage.href=https://{host}"'
}

test_deploy_script_calls_ensure_hub() {
  local deploy_script
  deploy_script="$(apps_render_deploy_script)"

  assert_contains_text "$deploy_script" 'ENSURE_HUB_SH="/opt/openclaw/bin/ensure_hub.sh"'
  assert_contains_text "$deploy_script" 'if [[ "${HUB_ENABLE}" == "true" && "${HUB_AUTOCREATE_ON_FIRST_APP}" == "true" ]]; then'
  assert_contains_text "$deploy_script" '"${ENSURE_HUB_SH}"'
}

test_ensure_hub_script_contains_routes_and_homepage_runtime() {
  local ensure_hub_script
  ensure_hub_script="$(apps_render_ensure_hub_script)"

  assert_contains_text "$ensure_hub_script" 'HUB_SERVICE_NAME="hub"'
  assert_contains_text "$ensure_hub_script" 'ghcr.io/gethomepage/homepage:latest'
  assert_contains_text "$ensure_hub_script" 'traefik.http.routers.hub.rule='
  assert_contains_text "$ensure_hub_script" 'homepage'
  assert_contains_text "$ensure_hub_script" 'host: ${SOCKET_PROXY_ENDPOINT}'
  assert_contains_text "$ensure_hub_script" 'docker compose -f "${APPS_COMPOSE_FILE}" up -d "${HUB_SERVICE_NAME}"'
  if grep -Fq '/var/run/docker.sock:/var/run/docker.sock:ro' <<< "$ensure_hub_script"; then
    echo "Assertion failed: ensure_hub.sh should not mount docker.sock directly" >&2
    exit 1
  fi
}

main() {
  # shellcheck source=/dev/null
  source "${ROOT_DIR}/scripts/lib/common.sh"
  # shellcheck source=/dev/null
  source "${ROOT_DIR}/scripts/lib/apps.sh"
  setup_apps_context

  test_register_script_contains_homepage_labels_and_reserved_hub
  test_deploy_script_calls_ensure_hub
  test_ensure_hub_script_contains_routes_and_homepage_runtime
  echo "PASS: test_apps_hub_phase.sh"
}

main "$@"
