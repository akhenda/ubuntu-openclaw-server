#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_contains() {
  local file="$1"
  local pattern="$2"
  if ! grep -Fq "$pattern" "$file"; then
    echo "Assertion failed: expected '$pattern' in $file" >&2
    echo "--- output ---" >&2
    cat "$file" >&2
    exit 1
  fi
}

make_valid_env() {
  local out="$1"

  cat > "$out" <<'ENVEOF'
DOMAIN=akhenda.net
APPS_DOMAIN=akhenda.net
BOT_NAME=cherry
TUNNEL_UUID=123e4567-e89b-12d3-a456-426614174000
CF_ZONE_ID=0123456789abcdef0123456789abcdef
CF_API_TOKEN=abcdefghijklmnopqrstuvwxyz123456
TAILSCALE_AUTHKEY=tskey-auth-test-placeholder-0123456789abcdef
TAILSCALE_ALLOW_PLACEHOLDER_AUTHKEY=true
OPENCLAW_GATEWAY_TOKEN=tok_abcdefghijklmnopqrstuvwxyz
OPENCLAW_GATEWAY_PASSWORD=StrongPass1234!
ADMIN_USER=hendaz
RUNTIME_USER=openclaw
HOST_FQDN=node.akhenda.net
SSH_PORT=1773
ADMIN_USER_SHELL=/bin/bash
RUNTIME_USER_SHELL=/bin/bash
REMOVE_DEFAULT_UBUNTU_USER=false
ADMIN_SSH_PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBASE64PLACEHOLDERKEYEXAMPLE1234567890 hendaz@test"
FIREWALL_ENABLE=false
EDGE_ENABLE=false
DNS_ENABLE=false
OPENCLAW_ENABLE=false
APPS_ENABLE=false
REPORT_ENABLE=false
VERIFY_ENABLE=false
OH_MY_ZSH_ENABLE=false
REPORT_OWNER_NAME=Joseph
EDGE_NETWORK_NAME=openclaw-edge
EDGE_SUBNET=172.30.0.0/24
TRAEFIK_IP=172.30.0.2
CLOUDFLARED_IP=172.30.0.3
OPENCLAW_GATEWAY_IP=172.30.0.10
ENVEOF
}

test_update_script_dry_run_uses_current_repo_without_pull() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap '[[ -n "${tmp_dir:-}" ]] && rm -rf "${tmp_dir}"' RETURN

  local env_file="$tmp_dir/.env"
  local output_file="$tmp_dir/output.log"

  make_valid_env "$env_file"

  bash "$ROOT_DIR/scripts/update_openclaw.sh" --config "$env_file" --dry-run >"$output_file" 2>&1

  assert_contains "$output_file" "[update] repo root: ${ROOT_DIR}"
  assert_contains "$output_file" "[update] using current checked-out repository state"
  assert_contains "$output_file" "[dry-run] bash ${ROOT_DIR}/scripts/install.sh --check-config --config ${env_file}"
  assert_contains "$output_file" "[dry-run] bash ${ROOT_DIR}/scripts/install.sh --config ${env_file} --print-config --dry-run"
  assert_contains "$output_file" "[update] dry-run complete"
}

test_update_script_dry_run_can_request_pull() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap '[[ -n "${tmp_dir:-}" ]] && rm -rf "${tmp_dir}"' RETURN

  local env_file="$tmp_dir/.env"
  local output_file="$tmp_dir/output.log"

  make_valid_env "$env_file"

  bash "$ROOT_DIR/scripts/update_openclaw.sh" --config "$env_file" --dry-run --pull >"$output_file" 2>&1

  assert_contains "$output_file" "[update] refreshing repository with git pull --ff-only"
  assert_contains "$output_file" "[dry-run] git -C ${ROOT_DIR} pull --ff-only"
}

test_update_script_dry_run_can_override_version_and_restart_services() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap '[[ -n "${tmp_dir:-}" ]] && rm -rf "${tmp_dir}"' RETURN

  local env_file="$tmp_dir/.env"
  local output_file="$tmp_dir/output.log"

  make_valid_env "$env_file"

  bash "$ROOT_DIR/scripts/update_openclaw.sh" --config "$env_file" --dry-run --npm-version latest >"$output_file" 2>&1

  assert_contains "$output_file" "[update] overriding OPENCLAW_NPM_VERSION=latest for this run"
  assert_contains "$output_file" "[dry-run] bash ${ROOT_DIR}/scripts/install.sh --check-config --config "
  assert_contains "$output_file" "OPENCLAW_NPM_VERSION=latest"
  assert_contains "$output_file" "[dry-run] systemctl restart openclaw-gateway.service"
  assert_contains "$output_file" "[dry-run] systemctl restart openclaw-apps.service"
}

main() {
  test_update_script_dry_run_uses_current_repo_without_pull
  test_update_script_dry_run_can_request_pull
  test_update_script_dry_run_can_override_version_and_restart_services
  echo "PASS: test_update_script.sh"
}

main "$@"
