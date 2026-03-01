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

assert_contains_one_of() {
  local file="$1"
  local pattern_a="$2"
  local pattern_b="$3"
  if grep -Fq "$pattern_a" "$file"; then
    return 0
  fi
  if grep -Fq "$pattern_b" "$file"; then
    return 0
  fi
  echo "Assertion failed: expected one of '$pattern_a' or '$pattern_b' in $file" >&2
  echo "--- output ---" >&2
  cat "$file" >&2
  exit 1
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
EDGE_NETWORK_NAME=openclaw-edge
EDGE_SUBNET=172.30.0.0/24
TRAEFIK_IP=172.30.0.2
CLOUDFLARED_IP=172.30.0.3
OPENCLAW_GATEWAY_IP=172.30.0.10
OH_MY_ZSH_ENABLE=false
REPORT_OWNER_NAME=Joseph
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

test_tailscale_phase_dry_run_installs_and_configures_service() {
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
  bash "$ROOT_DIR/scripts/install.sh" --config "$env_file" --dry-run >"$output_file" 2>&1

  assert_contains "$output_file" "[tailscale] configuring tailscale baseline"
  assert_contains "$output_file" "pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg"
  assert_contains "$output_file" "apt-get install -y --no-install-recommends tailscale"
  assert_contains_one_of "$output_file" "systemctl enable --now tailscaled" "systemctl not available; skipping tailscaled enablement"
  assert_contains "$output_file" "placeholder authkey allowed for test mode; skipping tailscale up"
  assert_contains "$output_file" "[tailscale] tailscale baseline complete"
}

test_tailscale_phase_placeholder_requires_explicit_test_flag() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap '[[ -n "${tmp_dir:-}" ]] && rm -rf "${tmp_dir}"' RETURN

  local env_file="$tmp_dir/.env"
  local output_file="$tmp_dir/output.log"

  make_valid_env "$env_file"
  printf '\nTAILSCALE_ALLOW_PLACEHOLDER_AUTHKEY=false\n' >> "$env_file"

  set +e
  bash "$ROOT_DIR/scripts/install.sh" --check-config --config "$env_file" >"$output_file" 2>&1
  local rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    echo "Assertion failed: expected config validation failure for placeholder authkey without test flag" >&2
    cat "$output_file" >&2
    exit 1
  fi

  assert_contains "$output_file" "TAILSCALE_AUTHKEY uses placeholder value"
}

test_tailscale_phase_passes_extra_args_to_tailscale_up() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap '[[ -n "${tmp_dir:-}" ]] && rm -rf "${tmp_dir}"' RETURN

  local env_file="$tmp_dir/.env"
  local output_file="$tmp_dir/output.log"

  make_valid_env "$env_file"
  perl -0pi -e 's/TAILSCALE_AUTHKEY=.*/TAILSCALE_AUTHKEY=tskey-auth-live-example-0123456789abcdef/; s/TAILSCALE_ALLOW_PLACEHOLDER_AUTHKEY=.*/TAILSCALE_ALLOW_PLACEHOLDER_AUTHKEY=false/' "$env_file"
  printf '\nTAILSCALE_EXTRA_ARGS=--accept-routes\n' >> "$env_file"
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
  bash "$ROOT_DIR/scripts/install.sh" --config "$env_file" --dry-run >"$output_file" 2>&1

  assert_contains "$output_file" "tailscale up --authkey tskey-auth-live-example-0123456789abcdef --hostname cherry-hendaz --ssh --accept-routes"
  assert_not_contains "$output_file" "placeholder authkey allowed for test mode"
}

main() {
  test_tailscale_phase_dry_run_installs_and_configures_service
  test_tailscale_phase_placeholder_requires_explicit_test_flag
  test_tailscale_phase_passes_extra_args_to_tailscale_up
  echo "PASS: test_tailscale_phase.sh"
}

main "$@"
