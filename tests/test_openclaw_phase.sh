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
OPENCLAW_ENABLE=true
OPENCLAW_ROOT_DIR=${edge_root}/openclaw
OPENCLAW_SOURCE_DIR=${edge_root}/openclaw-src
OPENCLAW_SOURCE_REPO=https://github.com/openclaw/openclaw.git
OPENCLAW_SOURCE_REF=main
OPENCLAW_SYNC_SOURCE=true
OPENCLAW_RUNTIME_HOME=/home/openclaw
OPENCLAW_NPM_PREFIX=/home/openclaw/.npm-global
OPENCLAW_NPM_PACKAGE=openclaw
OPENCLAW_NPM_VERSION=latest
OPENCLAW_BIN=/home/openclaw/.npm-global/bin/openclaw
OPENCLAW_IMAGE=openclaw:local
OPENCLAW_BUILD_IMAGE=true
OPENCLAW_START_STACK=true
OPENCLAW_MANAGE_SYSTEMD=true
OPENCLAW_GATEWAY_PORT=18789
OPENCLAW_MISSION_CONTROL_GATEWAY_HOST=gateway.akhenda.net
OPENCLAW_CONFIG_FILE=/home/openclaw/.openclaw/openclaw.json
OPENCLAW_POLICY_FILE=/home/openclaw/.openclaw/workspace/policies/deploy/AGENTS.md
OPENCLAW_POLICY_INJECTION=true
OPENCLAW_SYSTEMD_UNIT=${edge_root}/openclaw-gateway.service
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

test_openclaw_phase_dry_run_applies_runtime() {
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
  DOCKER_BIN=docker \
  bash "$ROOT_DIR/scripts/install.sh" --config "$env_file" --dry-run >"$output_file" 2>&1

  assert_contains "$output_file" "[openclaw] configuring OpenClaw runtime"
  assert_contains "$output_file" "git clone --branch main --depth 1 https://github.com/openclaw/openclaw.git ${edge_root}/openclaw-src"
  assert_contains "$output_file" "npm install -g openclaw@latest"
  assert_contains "$output_file" "[openclaw] [dry-run] would update /home/openclaw/.openclaw/openclaw.json"
  assert_contains "$output_file" "[openclaw] [dry-run] would update ${edge_root}/openclaw/.env"
  assert_contains "$output_file" "[openclaw] [dry-run] would update /home/openclaw/.openclaw/workspace/policies/deploy/AGENTS.md"
  assert_contains "$output_file" "[openclaw] [dry-run] would update /home/openclaw/.openclaw/workspace/policies/deploy/APP_BUILDER.md"
  assert_contains "$output_file" "[openclaw] [dry-run] would update /home/openclaw/.openclaw/workspace/APP_BUILDER.md"
  assert_contains "$output_file" "[openclaw] [dry-run] would update /home/openclaw/.openclaw/workspace/policies/deploy/publish_workspace_app.sh"
  assert_contains "$output_file" "[openclaw] [dry-run] would update /home/openclaw/.openclaw/skills/app_builder/SKILL.md"
  assert_contains "$output_file" "[openclaw] [dry-run] would create /opt/openclaw/AGENTS.md"
  assert_contains "$output_file" "[openclaw] [dry-run] would create /opt/openclaw/infra/global-compose/docker-compose.yml"
  assert_contains "$output_file" "[openclaw] [dry-run] would create /opt/openclaw/infra/global-compose/.env"
  assert_contains "$output_file" "[openclaw] [dry-run] would update /usr/local/bin/openclaw"
  assert_contains "$output_file" "[openclaw] OpenClaw runtime setup complete"
}

test_openclaw_phase_can_be_disabled() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap '[[ -n "${tmp_dir:-}" ]] && rm -rf "${tmp_dir}"' RETURN

  local edge_root="$tmp_dir/root"
  local env_file="$tmp_dir/.env"
  local output_file="$tmp_dir/output.log"

  make_valid_env "$env_file" "$edge_root"
  make_common_state "$tmp_dir"
  printf '\nOPENCLAW_ENABLE=false\n' >> "$env_file"

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

  assert_contains "$output_file" "OPENCLAW_ENABLE=false; skipping OpenClaw runtime setup"
  assert_not_contains "$output_file" "openclaw/config/openclaw.json"
}

test_openclaw_phase_skips_source_sync_when_disabled() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap '[[ -n "${tmp_dir:-}" ]] && rm -rf "${tmp_dir}"' RETURN

  local edge_root="$tmp_dir/root"
  local env_file="$tmp_dir/.env"
  local output_file="$tmp_dir/output.log"

  make_valid_env "$env_file" "$edge_root"
  make_common_state "$tmp_dir"
  printf '\nOPENCLAW_SYNC_SOURCE=false\n' >> "$env_file"

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

  assert_contains "$output_file" "[openclaw] OPENCLAW_SYNC_SOURCE=false; skipping source repository sync"
  assert_not_contains "$output_file" "git clone --branch main --depth 1 https://github.com/openclaw/openclaw.git ${edge_root}/openclaw-src"
}

test_openclaw_policy_injection_lock_is_enforced() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap '[[ -n "${tmp_dir:-}" ]] && rm -rf "${tmp_dir}"' RETURN

  local edge_root="$tmp_dir/root"
  local env_file="$tmp_dir/.env"
  local output_file="$tmp_dir/output.log"

  make_valid_env "$env_file" "$edge_root"
  printf '\nOPENCLAW_POLICY_INJECTION=false\n' >> "$env_file"

  set +e
  bash "$ROOT_DIR/scripts/install.sh" --check-config --config "$env_file" >"$output_file" 2>&1
  local rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    echo "Assertion failed: expected config validation failure for OPENCLAW_POLICY_INJECTION=false" >&2
    cat "$output_file" >&2
    exit 1
  fi

  assert_contains "$output_file" "OPENCLAW_POLICY_INJECTION must remain true"
}

test_openclaw_wrapper_forwards_runtime_env() {
  local rendered
  rendered="$(bash -lc "source '$ROOT_DIR/scripts/lib/openclaw.sh'; \
    RUNTIME_USER=openclaw; OPENCLAW_ROOT_DIR=/opt/openclaw/openclaw; \
    OPENCLAW_BIN=/home/openclaw/.npm-global/bin/openclaw; \
    OPENCLAW_NPM_PREFIX=/home/openclaw/.npm-global; \
    OPENCLAW_RUNTIME_HOME=/home/openclaw; openclaw_render_cli_wrapper")"

  assert_text_contains "$rendered" 'if [[ -r "${OPENCLAW_ENV_FILE}" ]]; then'
  assert_text_contains "$rendered" 'OPENCLAW_GATEWAY_PASSWORD="${OPENCLAW_GATEWAY_PASSWORD:-}"'
  assert_text_contains "$rendered" 'OPENCLAW_CONFIG_FILE="${OPENCLAW_CONFIG_FILE:-}"'
}

test_openclaw_config_bootstraps_app_builder_policy() {
  local rendered
  rendered="$(bash -lc "source '$ROOT_DIR/scripts/lib/openclaw.sh'; \
    BOT_NAME=mckay; APPS_DOMAIN=akhenda.net; TRAEFIK_IP=172.30.0.2; \
    MISSION_CONTROL_ENABLE=true; MISSION_CONTROL_HOST=mission-control.akhenda.net; \
    openclaw_render_config_json")"

  assert_text_contains "$rendered" '"policies/deploy/AGENTS.md", "policies/deploy/APP_BUILDER.md", "APP_BUILDER.md"'
  assert_text_contains "$rendered" '"allowedOrigins": ["https://mckay.akhenda.net", "https://mission-control.akhenda.net"]'
}

test_openclaw_renders_global_compose_env_with_real_values() {
  local rendered
  rendered="$(bash -lc "source '$ROOT_DIR/scripts/lib/openclaw.sh'; \
    DOMAIN=akhenda.net; APPS_DOMAIN=akhenda.net; BOT_NAME=mckay; \
    openclaw_render_global_compose_env")"

  assert_text_contains "$rendered" 'BASE_DOMAIN=akhenda.net'
  assert_text_contains "$rendered" 'BOT_NAME=mckay'
}

test_openclaw_publish_script_searches_multiple_workspace_roots() {
  local rendered
  rendered="$(bash -lc "source '$ROOT_DIR/scripts/lib/openclaw.sh'; \
    OPENCLAW_RUNTIME_HOME=/home/openclaw; OPENCLAW_ROOT_DIR=/opt/openclaw/openclaw; \
    APPS_ROOT_DIR=/opt/openclaw/apps; APPS_DEPLOY_SCRIPT=/opt/openclaw/bin/deploy_app.sh; \
    openclaw_render_workspace_publish_script")"

  assert_text_contains "$rendered" 'SANDBOX_WORKSPACE_ROOT="/home/node/.openclaw/workspace"'
  assert_text_contains "$rendered" 'LEGACY_WORKSPACE_ROOT="/opt/openclaw/openclaw/workspace"'
  assert_text_contains "$rendered" 'for root in "${WORKSPACE_ROOT}" "${SANDBOX_WORKSPACE_ROOT}" "${LEGACY_WORKSPACE_ROOT}"; do'
  assert_text_contains "$rendered" 'echo "Checked roots:" >&2'
  assert_text_contains "$rendered" 'echo "Using source app directory: ${SRC_DIR}"'
}

test_openclaw_merges_existing_config_without_dropping_state() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap '[[ -n "${tmp_dir:-}" ]] && rm -rf "${tmp_dir}"' RETURN

  local cfg_file="$tmp_dir/openclaw.json"
  cat > "$cfg_file" <<'JSON'
{
  "wizard": { "completed": true },
  "hooks": {
    "internal": {
      "entries": {
        "bootstrap-extra-files": {
          "enabled": true
        }
      }
    }
  }
}
JSON

  local merged
  merged="$(bash -lc "source '$ROOT_DIR/scripts/lib/common.sh'; source '$ROOT_DIR/scripts/lib/openclaw.sh'; \
    OPENCLAW_CONFIG_FILE='$cfg_file'; DRY_RUN=false; \
    desired='{\"hooks\":{\"internal\":{\"entries\":{\"bootstrap-extra-files\":{\"enabled\":true,\"paths\":[\"policies/deploy/AGENTS.md\",\"policies/deploy/APP_BUILDER.md\",\"APP_BUILDER.md\"]}}}}}'; \
    openclaw_merge_config_json_with_existing \"\$desired\"")"

  assert_text_contains "$merged" '"completed": true'
  assert_text_contains "$merged" '"policies/deploy/AGENTS.md"'
  assert_text_contains "$merged" '"policies/deploy/APP_BUILDER.md"'
  assert_text_contains "$merged" '"APP_BUILDER.md"'
}

main() {
  test_openclaw_phase_dry_run_applies_runtime
  test_openclaw_phase_can_be_disabled
  test_openclaw_phase_skips_source_sync_when_disabled
  test_openclaw_policy_injection_lock_is_enforced
  test_openclaw_wrapper_forwards_runtime_env
  test_openclaw_config_bootstraps_app_builder_policy
  test_openclaw_renders_global_compose_env_with_real_values
  test_openclaw_publish_script_searches_multiple_workspace_roots
  test_openclaw_merges_existing_config_without_dropping_state
  echo "PASS: test_openclaw_phase.sh"
}

main "$@"
