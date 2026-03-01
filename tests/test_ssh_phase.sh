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
}

test_ssh_phase_dry_run_applies_hardening_changes() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap '[[ -n "${tmp_dir:-}" ]] && rm -rf "${tmp_dir}"' RETURN

  local env_file="$tmp_dir/.env"
  local output_file="$tmp_dir/output.log"
  local main_cfg="$tmp_dir/sshd_config"
  local sshd_dir="$tmp_dir/sshd_config.d"
  local dropin_cfg="$sshd_dir/99-openclaw-hardening.conf"

  make_valid_env "$env_file"
  make_common_state "$tmp_dir"

  cat > "$main_cfg" <<'SSHEOF'
Port 22
PermitRootLogin yes
SSHEOF

  mkdir -p "$sshd_dir"

  OS_RELEASE_FILE="$tmp_dir/os-release" \
  USER_PASSWD_FILE="$tmp_dir/passwd" \
  USER_GROUP_FILE="$tmp_dir/group" \
  SUDOERS_FILE="$tmp_dir/sudoers" \
  SSHD_MAIN_CONFIG="$main_cfg" \
  SSHD_CONFIG_DIR="$sshd_dir" \
  SSHD_HARDENING_FILE="$dropin_cfg" \
  CURRENT_LOGIN_USER="hendaz" \
  DOCKER_ARCH=amd64 \
  bash "$ROOT_DIR/scripts/install.sh" --config "$env_file" --dry-run >"$output_file" 2>&1

  assert_contains "$output_file" "[ssh] configuring ssh hardening"
  assert_contains "$output_file" "sshd include directive missing"
  assert_contains "$output_file" "[ssh] [dry-run] would update $main_cfg"
  assert_contains "$output_file" "[ssh] [dry-run] would update $dropin_cfg"
  assert_contains "$output_file" "would validate ssh config"
  assert_contains "$output_file" "would restart ssh service"
  assert_contains "$output_file" "[ssh] ssh hardening applied"
}

test_ssh_phase_dry_run_no_change_is_idempotent() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap '[[ -n "${tmp_dir:-}" ]] && rm -rf "${tmp_dir}"' RETURN

  local env_file="$tmp_dir/.env"
  local output_file="$tmp_dir/output.log"
  local main_cfg="$tmp_dir/sshd_config"
  local sshd_dir="$tmp_dir/sshd_config.d"
  local dropin_cfg="$sshd_dir/99-openclaw-hardening.conf"

  make_valid_env "$env_file"
  make_common_state "$tmp_dir"

  cat > "$main_cfg" <<'SSHEOF'
Include /etc/ssh/sshd_config.d/*.conf
Port 22
SSHEOF

  mkdir -p "$sshd_dir"
  bash -c "source \"$ROOT_DIR/scripts/lib/ssh.sh\"; SSH_PORT=1773; ADMIN_USER=hendaz; ssh_render_hardening_dropin" > "$dropin_cfg"

  OS_RELEASE_FILE="$tmp_dir/os-release" \
  USER_PASSWD_FILE="$tmp_dir/passwd" \
  USER_GROUP_FILE="$tmp_dir/group" \
  SUDOERS_FILE="$tmp_dir/sudoers" \
  SSHD_MAIN_CONFIG="$main_cfg" \
  SSHD_CONFIG_DIR="$sshd_dir" \
  SSHD_HARDENING_FILE="$dropin_cfg" \
  CURRENT_LOGIN_USER="hendaz" \
  DOCKER_ARCH=amd64 \
  bash "$ROOT_DIR/scripts/install.sh" --config "$env_file" --dry-run >"$output_file" 2>&1

  assert_contains "$output_file" "sshd include directive already present"
  assert_contains "$output_file" "no changes for $dropin_cfg"
  assert_contains "$output_file" "[ssh] no sshd config changes detected"
  assert_not_contains "$output_file" "would restart ssh service"
}

main() {
  test_ssh_phase_dry_run_applies_hardening_changes
  test_ssh_phase_dry_run_no_change_is_idempotent
  echo "PASS: test_ssh_phase.sh"
}

main "$@"
