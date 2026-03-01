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
OPENCLAW_GATEWAY_TOKEN=tok_abcdefghijklmnopqrstuvwxyz
OPENCLAW_GATEWAY_PASSWORD=StrongPass1234!
ADMIN_USER=hendaz
RUNTIME_USER=openclaw
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
ENVEOF
}

test_user_phase_dry_run_emits_expected_commands() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap '[[ -n "${tmp_dir:-}" ]] && rm -rf "${tmp_dir}"' RETURN

  local env_file="$tmp_dir/.env"
  local os_release_file="$tmp_dir/os-release"
  local passwd_file="$tmp_dir/passwd"
  local group_file="$tmp_dir/group"
  local sudoers_file="$tmp_dir/sudoers"
  local output_file="$tmp_dir/output.log"

  make_valid_env "$env_file"

  cat > "$os_release_file" <<'OSEOF'
ID=ubuntu
VERSION_ID="24.04"
VERSION_CODENAME=noble
OSEOF

  cat > "$passwd_file" <<'PWEOF'
root:x:0:0:root:/root:/bin/bash
ubuntu:x:1000:1000:Ubuntu:/home/ubuntu:/bin/bash
PWEOF

  cat > "$group_file" <<'GREOF'
root:x:0:
sudo:x:27:
ubuntu:x:1000:
GREOF

  cat > "$sudoers_file" <<'SUEOF'
%sudo ALL=(ALL:ALL) ALL
SUEOF

  OS_RELEASE_FILE="$os_release_file" \
  USER_PASSWD_FILE="$passwd_file" \
  USER_GROUP_FILE="$group_file" \
  SUDOERS_FILE="$sudoers_file" \
  CURRENT_LOGIN_USER="hendaz" \
  DOCKER_ARCH=amd64 \
  bash "$ROOT_DIR/scripts/install.sh" --config "$env_file" --dry-run >"$output_file" 2>&1

  assert_contains "$output_file" "[user] configuring dual-user model"
  assert_contains "$output_file" "useradd --create-home --shell /bin/bash --groups sudo hendaz"
  assert_contains "$output_file" "useradd --create-home --shell /bin/bash --user-group openclaw"
  assert_contains "$output_file" "usermod -L openclaw"
  assert_contains "$output_file" "authorized_keys"
  assert_contains "$output_file" "userdel -r ubuntu"
  assert_contains "$output_file" "[user] dual-user setup complete"
}

test_user_phase_blocks_ubuntu_self_removal() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap '[[ -n "${tmp_dir:-}" ]] && rm -rf "${tmp_dir}"' RETURN

  local env_file="$tmp_dir/.env"
  local os_release_file="$tmp_dir/os-release"
  local passwd_file="$tmp_dir/passwd"
  local group_file="$tmp_dir/group"
  local sudoers_file="$tmp_dir/sudoers"
  local output_file="$tmp_dir/output.log"

  make_valid_env "$env_file"

  cat > "$os_release_file" <<'OSEOF'
ID=ubuntu
VERSION_ID="24.04"
VERSION_CODENAME=noble
OSEOF

  cat > "$passwd_file" <<'PWEOF'
root:x:0:0:root:/root:/bin/bash
ubuntu:x:1000:1000:Ubuntu:/home/ubuntu:/bin/bash
PWEOF

  cat > "$group_file" <<'GREOF'
root:x:0:
sudo:x:27:
ubuntu:x:1000:
GREOF

  cat > "$sudoers_file" <<'SUEOF'
%sudo ALL=(ALL:ALL) ALL
SUEOF

  set +e
  OS_RELEASE_FILE="$os_release_file" \
  USER_PASSWD_FILE="$passwd_file" \
  USER_GROUP_FILE="$group_file" \
  SUDOERS_FILE="$sudoers_file" \
  CURRENT_LOGIN_USER="ubuntu" \
  DOCKER_ARCH=amd64 \
  bash "$ROOT_DIR/scripts/install.sh" --config "$env_file" --dry-run >"$output_file" 2>&1
  local rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    echo "Assertion failed: expected failure when current login user is ubuntu" >&2
    cat "$output_file" >&2
    exit 1
  fi

  assert_contains "$output_file" "refusing to remove 'ubuntu'"
}

test_config_validation_requires_admin_ssh_key() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap '[[ -n "${tmp_dir:-}" ]] && rm -rf "${tmp_dir}"' RETURN

  local env_file="$tmp_dir/.env"
  local output_file="$tmp_dir/output.log"

  cat > "$env_file" <<'ENVEOF'
DOMAIN=akhenda.net
APPS_DOMAIN=akhenda.net
BOT_NAME=cherry
TUNNEL_UUID=123e4567-e89b-12d3-a456-426614174000
CF_ZONE_ID=0123456789abcdef0123456789abcdef
CF_API_TOKEN=abcdefghijklmnopqrstuvwxyz123456
OPENCLAW_GATEWAY_TOKEN=tok_abcdefghijklmnopqrstuvwxyz
OPENCLAW_GATEWAY_PASSWORD=StrongPass1234!
ADMIN_USER=hendaz
RUNTIME_USER=openclaw
SSH_PORT=1773
EDGE_NETWORK_NAME=openclaw-edge
EDGE_SUBNET=172.30.0.0/24
TRAEFIK_IP=172.30.0.2
CLOUDFLARED_IP=172.30.0.3
OPENCLAW_GATEWAY_IP=172.30.0.10
ENVEOF

  set +e
  bash "$ROOT_DIR/scripts/install.sh" --check-config --config "$env_file" >"$output_file" 2>&1
  local rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    echo "Assertion failed: expected missing ADMIN_SSH_PUBLIC_KEY validation error" >&2
    cat "$output_file" >&2
    exit 1
  fi

  assert_contains "$output_file" "Missing admin SSH key"
}

main() {
  test_user_phase_dry_run_emits_expected_commands
  test_user_phase_blocks_ubuntu_self_removal
  test_config_validation_requires_admin_ssh_key
  echo "PASS: test_user_phase.sh"
}

main "$@"
