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
  MISSION_CONTROL_ENABLE="true"
  MISSION_CONTROL_SERVICE_NAME="mission-control"
  MISSION_CONTROL_HOST="mission-control.example.com"
  MISSION_CONTROL_API_HOST="mission-control-api.example.com"
  MISSION_CONTROL_SOURCE_DIR="/opt/openclaw/apps/mission-control-src"
  MISSION_CONTROL_FRONTEND_DIR="/opt/openclaw/apps/mission-control-src/frontend"
  MISSION_CONTROL_AUTH_MODE="local"
  MISSION_CONTROL_LOCAL_AUTH_TOKEN="12345678901234567890123456789012345678901234567890"
  MISSION_CONTROL_DB_AUTO_MIGRATE="true"
  MISSION_CONTROL_POSTGRES_DB="mission_control"
  MISSION_CONTROL_POSTGRES_USER="postgres"
  MISSION_CONTROL_POSTGRES_PASSWORD="postgres"
  MISSION_CONTROL_RQ_QUEUE_NAME="default"
  MISSION_CONTROL_RQ_DISPATCH_THROTTLE_SECONDS="2.0"
  MISSION_CONTROL_RQ_DISPATCH_MAX_RETRIES="3"
  SOCKET_PROXY_ENDPOINT="http://docker-socket-proxy:2375"
}

test_register_script_contains_homepage_labels_and_reserved_hub() {
  local register_script
  register_script="$(apps_render_register_script)"

  assert_contains_text "$register_script" 'MISSION_CONTROL_SERVICE_NAME = os.environ.get("MISSION_CONTROL_SERVICE_NAME", "mission-control")'
  assert_contains_text "$register_script" 'reserved_names = {"traefik", RESERVED_BOT_NAME, HUB_SERVICE_NAME}'
  assert_contains_text "$register_script" 'reserved_names.add(MISSION_CONTROL_SERVICE_NAME)'
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
  assert_contains_text "$ensure_hub_script" 'SETTINGS_MARKER="# managed-by-openclaw-hub-style"'
  assert_contains_text "$ensure_hub_script" 'write_settings_profile() {'
  assert_contains_text "$ensure_hub_script" 'case "${HUB_STYLE_PROFILE}" in'
  assert_contains_text "$ensure_hub_script" 'modern-minimal)'
  assert_contains_text "$ensure_hub_script" 'minimal)'
  assert_contains_text "$ensure_hub_script" 'creative-minimal)'
  assert_contains_text "$ensure_hub_script" 'Unsupported HUB_STYLE_PROFILE: ${HUB_STYLE_PROFILE}'
  assert_contains_text "$ensure_hub_script" 'traefik.http.routers.hub.rule='
  assert_contains_text "$ensure_hub_script" 'homepage'
  assert_contains_text "$ensure_hub_script" 'elif grep -Fq "${SETTINGS_MARKER}" "${HUB_CONFIG_DIR}/settings.yaml"; then'
  assert_contains_text "$ensure_hub_script" 'if [[ ! -f "${HUB_CONFIG_DIR}/widgets.yaml" ]]; then'
  assert_contains_text "$ensure_hub_script" 'if [[ ! -f "${HUB_CONFIG_DIR}/docker.yaml" ]]; then'
  assert_contains_text "$ensure_hub_script" 'SOCKET_PROXY_PROTOCOL="http"'
  assert_contains_text "$ensure_hub_script" 'SOCKET_PROXY_HOST="${SOCKET_PROXY_ADDR%%:*}"'
  assert_contains_text "$ensure_hub_script" 'SOCKET_PROXY_PORT="${SOCKET_PROXY_ADDR##*:}"'
  assert_contains_text "$ensure_hub_script" 'host: ${SOCKET_PROXY_HOST}'
  assert_contains_text "$ensure_hub_script" 'port: ${SOCKET_PROXY_PORT}'
  assert_contains_text "$ensure_hub_script" 'protocol: ${SOCKET_PROXY_PROTOCOL}'
  assert_contains_text "$ensure_hub_script" 'services_config_path = os.path.join(hub_config_dir, "services.yaml")'
  assert_contains_text "$ensure_hub_script" 'MISSION_CONTROL_ENABLE="${MISSION_CONTROL_ENABLE:-true}"'
  assert_contains_text "$ensure_hub_script" 'MISSION_CONTROL_SERVICE_NAME="${MISSION_CONTROL_SERVICE_NAME:-mission-control}"'
  assert_contains_text "$ensure_hub_script" 'MISSION_CONTROL_HOST="${MISSION_CONTROL_HOST:-mission-control.example.com}"'
  assert_contains_text "$ensure_hub_script" 'MISSION_CONTROL_API_HOST="${MISSION_CONTROL_API_HOST:-mission-control-api.example.com}"'
  assert_contains_text "$ensure_hub_script" 'MISSION_CONTROL_SOURCE_DIR="${MISSION_CONTROL_SOURCE_DIR:-/opt/openclaw/apps/mission-control-src}"'
  assert_contains_text "$ensure_hub_script" 'MISSION_CONTROL_FRONTEND_DIR="${MISSION_CONTROL_FRONTEND_DIR:-/opt/openclaw/apps/mission-control-src/frontend}"'
  assert_contains_text "$ensure_hub_script" 'MISSION_CONTROL_AUTH_MODE="${MISSION_CONTROL_AUTH_MODE:-local}"'
  assert_contains_text "$ensure_hub_script" 'MISSION_CONTROL_LOCAL_AUTH_TOKEN="${MISSION_CONTROL_LOCAL_AUTH_TOKEN:-12345678901234567890123456789012345678901234567890}"'
  assert_contains_text "$ensure_hub_script" 'MISSION_CONTROL_DB_AUTO_MIGRATE="${MISSION_CONTROL_DB_AUTO_MIGRATE:-true}"'
  assert_contains_text "$ensure_hub_script" 'MISSION_CONTROL_POSTGRES_DB="${MISSION_CONTROL_POSTGRES_DB:-mission_control}"'
  assert_contains_text "$ensure_hub_script" 'MISSION_CONTROL_POSTGRES_USER="${MISSION_CONTROL_POSTGRES_USER:-postgres}"'
  assert_contains_text "$ensure_hub_script" 'MISSION_CONTROL_POSTGRES_PASSWORD="${MISSION_CONTROL_POSTGRES_PASSWORD:-postgres}"'
  assert_contains_text "$ensure_hub_script" 'MISSION_CONTROL_RQ_QUEUE_NAME="${MISSION_CONTROL_RQ_QUEUE_NAME:-default}"'
  assert_contains_text "$ensure_hub_script" 'MISSION_CONTROL_RQ_DISPATCH_THROTTLE_SECONDS="${MISSION_CONTROL_RQ_DISPATCH_THROTTLE_SECONDS:-2.0}"'
  assert_contains_text "$ensure_hub_script" 'MISSION_CONTROL_RQ_DISPATCH_MAX_RETRIES="${MISSION_CONTROL_RQ_DISPATCH_MAX_RETRIES:-3}"'
  assert_contains_text "$ensure_hub_script" 'homepage.name=Mission Control'
  assert_contains_text "$ensure_hub_script" 'postgres:16-alpine'
  assert_contains_text "$ensure_hub_script" 'redis:7-alpine'
  assert_contains_text "$ensure_hub_script" 'backend/Dockerfile'
  assert_contains_text "$ensure_hub_script" 'scripts/rq-docker'
  assert_contains_text "$ensure_hub_script" 'f"traefik.http.services.{mission_control_backend_service_name}.loadbalancer.server.port=8000"'
  assert_contains_text "$ensure_hub_script" 'NEXT_PUBLIC_API_URL'
  assert_contains_text "$ensure_hub_script" 'NEXT_PUBLIC_AUTH_MODE'
  assert_contains_text "$ensure_hub_script" 'MISSION_CONTROL_DB_SERVICE_NAME="${MISSION_CONTROL_SERVICE_NAME}-db"'
  assert_contains_text "$ensure_hub_script" 'MISSION_CONTROL_WORKER_SERVICE_NAME="${MISSION_CONTROL_SERVICE_NAME}-webhook-worker"'
  assert_contains_text "$ensure_hub_script" 'docker compose --project-directory "${PROJECT_DIR}" -f "${APPS_COMPOSE_FILE}" up -d'
  assert_contains_text "$ensure_hub_script" '"${MISSION_CONTROL_BACKEND_SERVICE_NAME}"'
  assert_contains_text "$ensure_hub_script" '"${MISSION_CONTROL_WORKER_SERVICE_NAME}"'
  assert_contains_text "$ensure_hub_script" 'OK: wrote hub services catalog ->'
  assert_contains_text "$ensure_hub_script" 'docker compose --project-directory "${PROJECT_DIR}" -f "${APPS_COMPOSE_FILE}" up -d "${HUB_SERVICE_NAME}"'
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
