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
FIREWALL_ENABLE=true
FIREWALL_ALLOW_HTTP=true
FIREWALL_ALLOW_HTTPS=true
FIREWALL_EXTRA_TCP_PORTS=3000,8080,1773,22
OPENCLAW_ENABLE=true
OPENCLAW_GATEWAY_PORT=18789
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

test_firewall_phase_dry_run_applies_baseline() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap '[[ -n "${tmp_dir:-}" ]] && rm -rf "${tmp_dir}"' RETURN

  local env_file="$tmp_dir/.env"
  local output_file="$tmp_dir/output.log"

  make_valid_env "$env_file"
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
  UFW_BIN=ufw \
  bash "$ROOT_DIR/scripts/install.sh" --config "$env_file" --dry-run >"$output_file" 2>&1

  assert_contains "$output_file" "[firewall] configuring ufw baseline"
  assert_contains "$output_file" "ufw default deny incoming"
  assert_contains "$output_file" "ufw default allow outgoing"
  assert_contains "$output_file" "ufw allow 1773/tcp"
  assert_contains "$output_file" "ufw deny 22/tcp"
  assert_contains "$output_file" "ufw allow 80/tcp"
  assert_contains "$output_file" "ufw allow 443/tcp"
  assert_contains "$output_file" "allowing edge subnet 172.30.0.0/24 to OpenClaw gateway port 18789"
  assert_contains "$output_file" "ufw allow from 172.30.0.0/24 to any port 18789 proto tcp"
  assert_contains "$output_file" "allowing extra TCP port 3000"
  assert_contains "$output_file" "allowing extra TCP port 8080"
  assert_contains "$output_file" "skipping duplicate/implicit port 1773"
  assert_contains "$output_file" "skipping extra allow for port 22"
  assert_contains "$output_file" "ufw --force enable"
  assert_contains "$output_file" "[firewall] ufw baseline applied"
}

test_firewall_phase_can_be_disabled() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap '[[ -n "${tmp_dir:-}" ]] && rm -rf "${tmp_dir}"' RETURN

  local env_file="$tmp_dir/.env"
  local output_file="$tmp_dir/output.log"

  make_valid_env "$env_file"
  make_common_state "$tmp_dir"
  printf '\nFIREWALL_ENABLE=false\n' >> "$env_file"

  OS_RELEASE_FILE="$tmp_dir/os-release" \
  USER_PASSWD_FILE="$tmp_dir/passwd" \
  USER_GROUP_FILE="$tmp_dir/group" \
  SUDOERS_FILE="$tmp_dir/sudoers" \
  SSHD_MAIN_CONFIG="$tmp_dir/sshd_config" \
  SSHD_CONFIG_DIR="$tmp_dir/sshd_config.d" \
  SSHD_HARDENING_FILE="$tmp_dir/sshd_config.d/99-openclaw-hardening.conf" \
  CURRENT_LOGIN_USER="hendaz" \
  DOCKER_ARCH=amd64 \
  UFW_BIN=ufw \
  bash "$ROOT_DIR/scripts/install.sh" --config "$env_file" --dry-run >"$output_file" 2>&1

  assert_contains "$output_file" "FIREWALL_ENABLE=false; skipping ufw configuration"
  assert_not_contains "$output_file" "ufw default deny incoming"
}

test_firewall_phase_blocks_public_openclaw_port_rule() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap '[[ -n "${tmp_dir:-}" ]] && rm -rf "${tmp_dir}"' RETURN

  local env_file="$tmp_dir/.env"
  local output_file="$tmp_dir/output.log"

  make_valid_env "$env_file"
  make_common_state "$tmp_dir"
  printf '\nFIREWALL_EXTRA_TCP_PORTS=3000,18789\n' >> "$env_file"

  set +e
  OS_RELEASE_FILE="$tmp_dir/os-release" \
  USER_PASSWD_FILE="$tmp_dir/passwd" \
  USER_GROUP_FILE="$tmp_dir/group" \
  SUDOERS_FILE="$tmp_dir/sudoers" \
  SSHD_MAIN_CONFIG="$tmp_dir/sshd_config" \
  SSHD_CONFIG_DIR="$tmp_dir/sshd_config.d" \
  SSHD_HARDENING_FILE="$tmp_dir/sshd_config.d/99-openclaw-hardening.conf" \
  CURRENT_LOGIN_USER="hendaz" \
  DOCKER_ARCH=amd64 \
  UFW_BIN=ufw \
  bash "$ROOT_DIR/scripts/install.sh" --config "$env_file" --check-config >"$output_file" 2>&1
  local rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    echo "Assertion failed: expected config validation to fail when FIREWALL_EXTRA_TCP_PORTS includes OPENCLAW_GATEWAY_PORT" >&2
    echo "--- output ---" >&2
    cat "$output_file" >&2
    exit 1
  fi

  assert_contains "$output_file" "must not include OPENCLAW_GATEWAY_PORT"
}

main() {
  test_firewall_phase_dry_run_applies_baseline
  test_firewall_phase_can_be_disabled
  test_firewall_phase_blocks_public_openclaw_port_rule
  echo "PASS: test_firewall_phase.sh"
}

main "$@"
