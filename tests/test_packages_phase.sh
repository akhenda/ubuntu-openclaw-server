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
REMOVE_DEFAULT_UBUNTU_USER=true
ADMIN_SSH_PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBASE64PLACEHOLDERKEYEXAMPLE1234567890 hendaz@test"
EDGE_NETWORK_NAME=openclaw-edge
EDGE_SUBNET=172.30.0.0/24
TRAEFIK_IP=172.30.0.2
CLOUDFLARED_IP=172.30.0.3
OPENCLAW_GATEWAY_IP=172.30.0.10
OH_MY_ZSH_ENABLE=false
ENVEOF
}

test_packages_phase_dry_run() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap '[[ -n "${tmp_dir:-}" ]] && rm -rf "${tmp_dir}"' RETURN

  local env_file="$tmp_dir/.env"
  local os_release_file="$tmp_dir/os-release"
  local output_file="$tmp_dir/output.log"

  make_valid_env "$env_file"

  cat > "$os_release_file" <<'OSEOF'
ID=ubuntu
VERSION_ID="24.04"
VERSION_CODENAME=noble
OSEOF

  OS_RELEASE_FILE="$os_release_file" \
  DOCKER_ARCH=amd64 \
  bash "$ROOT_DIR/scripts/install.sh" --config "$env_file" --dry-run >"$output_file" 2>&1

  assert_contains "$output_file" "[packages] Installing prerequisite OS packages"
  assert_contains "$output_file" "apt-get install -y --no-install-recommends ca-certificates curl git jq apache2-utils python3 python3-venv ufw fail2ban unattended-upgrades"
  assert_contains "$output_file" "download.docker.com/linux/ubuntu noble stable"
  assert_contains "$output_file" "docker-compose-plugin"
  assert_contains "$output_file" "[packages] prerequisites complete"
}

test_packages_phase_rejects_non_ubuntu() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap '[[ -n "${tmp_dir:-}" ]] && rm -rf "${tmp_dir}"' RETURN

  local env_file="$tmp_dir/.env"
  local os_release_file="$tmp_dir/os-release"
  local output_file="$tmp_dir/output.log"

  make_valid_env "$env_file"

  cat > "$os_release_file" <<'OSEOF'
ID=debian
VERSION_ID="12"
VERSION_CODENAME=bookworm
OSEOF

  set +e
  OS_RELEASE_FILE="$os_release_file" bash "$ROOT_DIR/scripts/install.sh" --config "$env_file" --dry-run >"$output_file" 2>&1
  local rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    echo "Assertion failed: expected non-zero exit for unsupported OS" >&2
    cat "$output_file" >&2
    exit 1
  fi

  assert_contains "$output_file" "Unsupported OS ID"
}

main() {
  test_packages_phase_dry_run
  test_packages_phase_rejects_non_ubuntu
  echo "PASS: test_packages_phase.sh"
}

main "$@"
