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

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  if grep -Fq "$pattern" "$file"; then
    echo "Assertion failed: did not expect '$pattern' in $file" >&2
    echo "--- output ---" >&2
    cat "$file" >&2
    exit 1
  fi
}

make_valid_env() {
  local out="$1"
  local edge_root="$2"
  local creds_file="$3"

  cat > "$out" <<ENVEOF
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
EDGE_ENABLE=true
EDGE_ROOT_DIR=${edge_root}
EDGE_START_STACK=true
EDGE_REQUIRE_TUNNEL_CREDENTIALS=true
TRAEFIK_IMAGE=traefik:v3.0
CLOUDFLARED_IMAGE=cloudflare/cloudflared:latest
TRAEFIK_DASHBOARD_HOST=traefik.akhenda.net
OPENCLAW_MISSION_CONTROL_GATEWAY_HOST=gateway.akhenda.net
TRAEFIK_DASHBOARD_USERS=admin:hashplaceholder
CLOUDFLARED_CREDENTIALS_FILE=${creds_file}
EDGE_NETWORK_NAME=openclaw-edge
EDGE_SUBNET=172.30.0.0/24
TRAEFIK_IP=172.30.0.2
CLOUDFLARED_IP=172.30.0.3
OPENCLAW_GATEWAY_IP=172.30.0.10
OH_MY_ZSH_ENABLE=false
ENVEOF
}

make_common_state() {
  local tmp_dir="$1"

  cat > "$tmp_dir/os-release" <<'OSEOF'
ID=ubuntu
VERSION_ID="24.04"
VERSION_CODENAME=noble
OSEOF

  cat > "$tmp_dir/passwd" <<'PWEOF'
root:x:0:0:root:/root:/bin/bash
hendaz:x:1001:1001:Admin:/home/hendaz:/bin/bash
openclaw:x:1002:1002:Runtime:/home/openclaw:/bin/bash
PWEOF

  cat > "$tmp_dir/group" <<'GREOF'
root:x:0:
sudo:x:27:hendaz
hendaz:x:1001:
openclaw:x:1002:
GREOF

  cat > "$tmp_dir/sudoers" <<'SUEOF'
%sudo ALL=(ALL:ALL) ALL
SUEOF

  cat > "$tmp_dir/sshd_config" <<'SSHEOF'
Include /etc/ssh/sshd_config.d/*.conf
Port 22
SSHEOF

  mkdir -p "$tmp_dir/sshd_config.d"
  bash -c "source '$ROOT_DIR/scripts/lib/ssh.sh'; SSH_PORT=1773; ADMIN_USER=hendaz; ssh_render_hardening_dropin" > "$tmp_dir/sshd_config.d/99-openclaw-hardening.conf"
}

test_edge_phase_dry_run_applies_stack() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap '[[ -n "${tmp_dir:-}" ]] && rm -rf "${tmp_dir}"' RETURN

  local edge_root="$tmp_dir/openclaw"
  local creds_file="$edge_root/edge/cloudflared/123e4567-e89b-12d3-a456-426614174000.json"
  local env_file="$tmp_dir/.env"
  local output_file="$tmp_dir/output.log"

  mkdir -p "$(dirname "$creds_file")"
  printf '{}' > "$creds_file"

  make_valid_env "$env_file" "$edge_root" "$creds_file"
  make_common_state "$tmp_dir"

  OS_RELEASE_FILE="$tmp_dir/os-release" \
  USER_PASSWD_FILE="$tmp_dir/passwd" \
  USER_GROUP_FILE="$tmp_dir/group" \
  SUDOERS_FILE="$tmp_dir/sudoers" \
  SSHD_MAIN_CONFIG="$tmp_dir/sshd_config" \
  SSHD_CONFIG_DIR="$tmp_dir/sshd_config.d" \
  SSHD_HARDENING_FILE="$tmp_dir/sshd_config.d/99-openclaw-hardening.conf" \
  CURRENT_LOGIN_USER="hendaz" \
  DOCKER_ARCH=amd64 \
  DOCKER_BIN=docker \
  bash "$ROOT_DIR/scripts/install.sh" --config "$env_file" --dry-run >"$output_file" 2>&1

  assert_contains "$output_file" "[edge] configuring edge stack"
  assert_contains "$output_file" "[edge] [dry-run] would update ${edge_root}/edge/traefik/traefik.yml"
  assert_contains "$output_file" "[edge] [dry-run] would update ${edge_root}/edge/cloudflared/config.yml"
  assert_contains "$output_file" "[edge] [dry-run] would update ${edge_root}/edge/docker-compose.yml"
  assert_contains "$output_file" "docker network inspect openclaw-edge"
  assert_contains "$output_file" "docker network create --subnet 172.30.0.0/24 openclaw-edge"
  assert_contains "$output_file" "docker compose -f ${edge_root}/edge/docker-compose.yml up -d"
  assert_contains "$output_file" "[edge] edge stack configuration complete"
}

test_edge_phase_skips_start_without_credentials() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap '[[ -n "${tmp_dir:-}" ]] && rm -rf "${tmp_dir}"' RETURN

  local edge_root="$tmp_dir/openclaw"
  local creds_file="$edge_root/edge/cloudflared/123e4567-e89b-12d3-a456-426614174000.json"
  local env_file="$tmp_dir/.env"
  local output_file="$tmp_dir/output.log"

  make_valid_env "$env_file" "$edge_root" "$creds_file"
  make_common_state "$tmp_dir"

  OS_RELEASE_FILE="$tmp_dir/os-release" \
  USER_PASSWD_FILE="$tmp_dir/passwd" \
  USER_GROUP_FILE="$tmp_dir/group" \
  SUDOERS_FILE="$tmp_dir/sudoers" \
  SSHD_MAIN_CONFIG="$tmp_dir/sshd_config" \
  SSHD_CONFIG_DIR="$tmp_dir/sshd_config.d" \
  SSHD_HARDENING_FILE="$tmp_dir/sshd_config.d/99-openclaw-hardening.conf" \
  CURRENT_LOGIN_USER="hendaz" \
  DOCKER_ARCH=amd64 \
  DOCKER_BIN=docker \
  bash "$ROOT_DIR/scripts/install.sh" --config "$env_file" --dry-run >"$output_file" 2>&1

  assert_contains "$output_file" "cloudflared credentials not found"
  assert_not_contains "$output_file" "docker compose -f ${edge_root}/edge/docker-compose.yml up -d"
}

main() {
  test_edge_phase_dry_run_applies_stack
  test_edge_phase_skips_start_without_credentials
  echo "PASS: test_edge_phase.sh"
}

main "$@"
