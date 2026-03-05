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

assert_text_contains() {
  local text="$1"
  local pattern="$2"
  if ! grep -Fq "$pattern" <<<"$text"; then
    echo "Assertion failed: expected '$pattern' in rendered text" >&2
    echo "--- rendered ---" >&2
    printf '%s\n' "$text" >&2
    exit 1
  fi
}

make_valid_env() {
  local out="$1"
  local edge_root="$2"

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
EDGE_ENABLE=false
DNS_ENABLE=false
OPENCLAW_ENABLE=false
APPS_ENABLE=true
APPS_ROOT_DIR=${edge_root}/apps
APPS_COMPOSE_FILE=${edge_root}/apps/docker-compose.yml
APPS_VENV_DIR=${edge_root}/.venv
DNS_BIN_DIR=${edge_root}/bin
APPS_REGISTER_SCRIPT=${edge_root}/bin/register_app.py
APPS_DEPLOY_SCRIPT=${edge_root}/bin/deploy_app.sh
APPS_SETUP_VENV=true
APPS_VENV_PYTHON=python3
MISSION_CONTROL_ENABLE=true
MISSION_CONTROL_SERVICE_NAME=mission-control
MISSION_CONTROL_HOST=mission-control.akhenda.net
MISSION_CONTROL_SOURCE_REPO=https://github.com/abhi1693/openclaw-mission-control.git
MISSION_CONTROL_SOURCE_REF=master
MISSION_CONTROL_SOURCE_DIR=${edge_root}/apps/mission-control-src
MISSION_CONTROL_FRONTEND_DIR=${edge_root}/apps/mission-control-src/frontend
MISSION_CONTROL_API_HOST=mission-control-api.akhenda.net
MISSION_CONTROL_AUTH_MODE=local
MISSION_CONTROL_LOCAL_AUTH_TOKEN=12345678901234567890123456789012345678901234567890
MISSION_CONTROL_DB_AUTO_MIGRATE=true
MISSION_CONTROL_POSTGRES_DB=mission_control
MISSION_CONTROL_POSTGRES_USER=postgres
MISSION_CONTROL_POSTGRES_PASSWORD=postgres
MISSION_CONTROL_RQ_QUEUE_NAME=default
MISSION_CONTROL_RQ_DISPATCH_THROTTLE_SECONDS=2.0
MISSION_CONTROL_RQ_DISPATCH_MAX_RETRIES=3
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

test_apps_phase_dry_run_generates_registry_and_helpers() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap '[[ -n "${tmp_dir:-}" ]] && rm -rf "${tmp_dir}"' RETURN

  local edge_root="$tmp_dir/root"
  local env_file="$tmp_dir/.env"
  local output_file="$tmp_dir/output.log"

  make_valid_env "$env_file" "$edge_root"
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

  assert_contains "$output_file" "[apps] configuring apps registry and helper scripts"
  assert_contains "$output_file" "install -d -m 0755 -o openclaw -g openclaw ${edge_root}/apps"
  assert_contains "$output_file" "python3 -m venv ${edge_root}/.venv"
  assert_contains "$output_file" "${edge_root}/.venv/bin/pip install ruamel.yaml"
  assert_contains "$output_file" "[apps] [dry-run] would update ${edge_root}/apps/docker-compose.yml"
  assert_contains "$output_file" "[apps] [dry-run] would update ${edge_root}/bin/register_app.py"
  assert_contains "$output_file" "[apps] [dry-run] would update ${edge_root}/bin/deploy_app.sh"
  assert_contains "$output_file" "[apps] ensuring Mission Control source at ${edge_root}/apps/mission-control-src"
  assert_contains "$output_file" "sudo -u openclaw -H /bin/bash -lc git clone --branch master --depth 1 https://github.com/abhi1693/openclaw-mission-control.git ${edge_root}/apps/mission-control-src"
  assert_contains "$output_file" "[apps] ensuring app runtime paths are owned by openclaw"
  assert_contains "$output_file" "chown -R openclaw:openclaw ${edge_root}/apps"
  assert_contains "$output_file" "install -d -m 0755 -o openclaw -g openclaw ${edge_root}/apps/hub-config"
  assert_contains "$output_file" "chown openclaw:openclaw ${edge_root}/apps/docker-compose.yml"
  assert_contains "$output_file" "[apps] ensuring hub service exists during install"
  assert_contains "$output_file" "/bin/bash ${edge_root}/bin/ensure_hub.sh"
  assert_contains "$output_file" "[apps] apps registry setup complete"
}

test_apps_deploy_script_uses_explicit_project_directory() {
  local rendered
  rendered="$(bash -lc "source '$ROOT_DIR/scripts/lib/apps.sh'; \
    APPS_COMPOSE_FILE=/opt/openclaw/apps/docker-compose.yml; \
    APPS_VENV_DIR=/opt/openclaw/.venv; \
    EDGE_NETWORK_NAME=openclaw-edge; \
    HUB_ENABLE=true; HUB_AUTOCREATE_ON_FIRST_APP=true; HUB_PRIMARY_HOST=hub.akhenda.net; \
    HUB_ALIAS_HOST=apps.akhenda.net; HUB_STYLE_PROFILE=modern-minimal; \
    APPS_DOMAIN=akhenda.net; BOT_NAME=mckay; APPS_REGISTER_SCRIPT=/opt/openclaw/bin/register_app.py; \
    DNS_BIN_DIR=/opt/openclaw/bin; APPS_DEPLOY_SCRIPT=/opt/openclaw/bin/deploy_app.sh; \
    apps_render_deploy_script")"

  assert_text_contains "$rendered" 'PROJECT_DIR="$(dirname "${APPS_COMPOSE_FILE}")"'
  assert_text_contains "$rendered" 'docker compose --project-directory "${PROJECT_DIR}" -f "${APPS_COMPOSE_FILE}" up -d --build "${APP_NAME}"'
}

test_apps_phase_can_be_disabled() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap '[[ -n "${tmp_dir:-}" ]] && rm -rf "${tmp_dir}"' RETURN

  local edge_root="$tmp_dir/root"
  local env_file="$tmp_dir/.env"
  local output_file="$tmp_dir/output.log"

  make_valid_env "$env_file" "$edge_root"
  make_common_state "$tmp_dir"
  printf '\nAPPS_ENABLE=false\n' >> "$env_file"

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

  assert_contains "$output_file" "APPS_ENABLE=false; skipping apps registry setup"
  assert_not_contains "$output_file" "register_app.py"
}

test_apps_phase_preserves_existing_compose_file() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap '[[ -n "${tmp_dir:-}" ]] && rm -rf "${tmp_dir}"' RETURN

  local edge_root="$tmp_dir/root"
  local env_file="$tmp_dir/.env"
  local output_file="$tmp_dir/output.log"

  make_valid_env "$env_file" "$edge_root"
  make_common_state "$tmp_dir"

  mkdir -p "${edge_root}/apps"
  cat > "${edge_root}/apps/docker-compose.yml" <<'EOF'
services:
  sample-app:
    image: sample:latest
EOF

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

  assert_contains "$output_file" "[apps] preserving existing compose file at ${edge_root}/apps/docker-compose.yml"
  assert_not_contains "$output_file" "[apps] [dry-run] would update ${edge_root}/apps/docker-compose.yml"
}

main() {
  test_apps_phase_dry_run_generates_registry_and_helpers
  test_apps_phase_can_be_disabled
  test_apps_phase_preserves_existing_compose_file
  test_apps_deploy_script_uses_explicit_project_directory
  echo "PASS: test_apps_phase.sh"
}

main "$@"
