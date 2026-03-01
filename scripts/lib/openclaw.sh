#!/usr/bin/env bash

openclaw_run_root() {
  if (( EUID == 0 )); then
    run_cmd "$@"
    return $?
  fi

  command_exists sudo || die "[openclaw] sudo is required when not running as root"
  run_cmd sudo "$@"
}

openclaw_run_as_runtime() {
  local runtime_home
  local runtime_path
  local shell_cmd=""
  local arg
  runtime_home="$(openclaw_runtime_home)"
  runtime_path="${OPENCLAW_NPM_PREFIX}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

  if ! command_exists sudo; then
    die "[openclaw] sudo is required to run commands as ${RUNTIME_USER}"
  fi

  for arg in "$@"; do
    shell_cmd+=" $(printf '%q' "${arg}")"
  done
  shell_cmd="${shell_cmd# }"

  run_cmd sudo -u "${RUNTIME_USER}" -H /bin/bash -lc \
    "cd $(printf '%q' "${runtime_home}") && export HOME=$(printf '%q' "${runtime_home}") && export PATH=$(printf '%q' "${runtime_path}") && ${shell_cmd}"
}

openclaw_runtime_home() {
  if [[ -n "${OPENCLAW_RUNTIME_HOME:-}" ]]; then
    printf '%s' "${OPENCLAW_RUNTIME_HOME}"
    return 0
  fi

  if declare -F user_home >/dev/null 2>&1; then
    local detected
    detected="$(user_home "${RUNTIME_USER}" || true)"
    if [[ -n "${detected}" ]]; then
      printf '%s' "${detected}"
      return 0
    fi
  fi

  printf '/home/%s' "${RUNTIME_USER}"
}

openclaw_write_content_if_changed() {
  local target="$1"
  local mode="$2"
  local content="$3"
  local owner="${4:-root:root}"

  local tmp_file
  tmp_file="$(mktemp)"
  printf '%s\n' "${content}" > "${tmp_file}"

  local changed="true"
  if [[ -f "${target}" ]] && cmp -s "${target}" "${tmp_file}"; then
    changed="false"
  fi

  if [[ "${changed}" == "false" ]]; then
    log_info "[openclaw] no changes for ${target}"
    rm -f "${tmp_file}"
    return 1
  fi

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[openclaw] [dry-run] would update ${target}"
    rm -f "${tmp_file}"
    return 0
  fi

  openclaw_run_root install -d -m 0755 "$(dirname "${target}")"
  openclaw_run_root cp "${tmp_file}" "${target}"
  openclaw_run_root chown "${owner}" "${target}"
  openclaw_run_root chmod "${mode}" "${target}"
  rm -f "${tmp_file}"
  return 0
}

openclaw_env_file_path() {
  printf '%s/.env' "${OPENCLAW_ROOT_DIR}"
}

openclaw_cli_wrapper_path() {
  printf '%s' "/usr/local/bin/openclaw"
}

openclaw_render_config_json() {
  local runtime_home
  runtime_home="$(openclaw_runtime_home)"

  cat <<EOF_JSON
{
  "agents": {
    "defaults": {
      "workspace": "${runtime_home}/.openclaw/workspace"
    }
  },
  "gateway": {
    "mode": "local",
    "trustedProxies": ["${TRAEFIK_IP}"],
    "allowRealIpFallback": false,
    "auth": {
      "mode": "password"
    },
    "controlUi": {
      "allowedOrigins": ["https://${BOT_NAME}.${APPS_DOMAIN}"]
    }
  },
  "hooks": {
    "internal": {
      "enabled": true,
      "entries": {
        "bootstrap-extra-files": {
          "enabled": true,
          "paths": ["policies/deploy/AGENTS.md"]
        }
      }
    }
  }
}
EOF_JSON
}

openclaw_render_cli_wrapper() {
  cat <<EOF_WRAPPER
#!/usr/bin/env bash
set -euo pipefail

RUNTIME_USER="${RUNTIME_USER}"
RUNTIME_HOME="$(openclaw_runtime_home)"
OPENCLAW_BIN="${OPENCLAW_BIN}"
OPENCLAW_PATH="$(dirname "${OPENCLAW_BIN}"):/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

if [[ ! -x "\${OPENCLAW_BIN}" ]]; then
  echo "OpenClaw binary not found at \${OPENCLAW_BIN}." >&2
  echo "Run the installer first: make run-install" >&2
  exit 1
fi

if [[ "\${USER:-}" == "\${RUNTIME_USER}" ]]; then
  exec env HOME="\${RUNTIME_HOME}" PATH="\${OPENCLAW_PATH}" "\${OPENCLAW_BIN}" "\$@"
fi

if ! command -v sudo >/dev/null 2>&1; then
  echo "sudo is required to run OpenClaw as \${RUNTIME_USER}." >&2
  exit 1
fi

exec sudo -u "\${RUNTIME_USER}" -H env \
  HOME="\${RUNTIME_HOME}" \
  PATH="\${OPENCLAW_PATH}" \
  "\${OPENCLAW_BIN}" "\$@"
EOF_WRAPPER
}

openclaw_render_env_file() {
  cat <<EOF_ENV
OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
OPENCLAW_GATEWAY_PASSWORD=${OPENCLAW_GATEWAY_PASSWORD}
OPENCLAW_GATEWAY_PORT=${OPENCLAW_GATEWAY_PORT}
OPENCLAW_RUNTIME_HOME=$(openclaw_runtime_home)
OPENCLAW_CONFIG_FILE=${OPENCLAW_CONFIG_FILE}
OPENCLAW_BIN=${OPENCLAW_BIN}
BOT_NAME=${BOT_NAME}
APPS_DOMAIN=${APPS_DOMAIN}
EOF_ENV
}

openclaw_render_policy_agents_md() {
  cat <<EOF_POLICY
# Deployment Rules (MUST FOLLOW)

## Reserved subdomains
Never create an app named:
- traefik
- ${BOT_NAME}
- hub

## Global stack + global apps compose
- The edge stack runs at: ${EDGE_ROOT_DIR}/edge/docker-compose.yml (Traefik + cloudflared + docker-socket-proxy when enabled). Do NOT modify it when adding apps.
- All apps must be added to the GLOBAL APPS COMPOSE:
  ${EDGE_ROOT_DIR}/apps/docker-compose.yml

## When you create a new runnable HTTP app
You MUST do all of the following:

1. Create the project directory:
   ${EDGE_ROOT_DIR}/apps/<appName>/
2. Add a Dockerfile (and any required source files) so the app can build.
3. Determine the internal app port (for example 3000).
4. Register + deploy using:
   ${EDGE_ROOT_DIR}/bin/deploy_app.sh <appName> <port>
5. Hub routing is mandatory:
   - Ensure hub exists at https://${HUB_PRIMARY_HOST}
   - App cards must resolve to https://<appName>.${APPS_DOMAIN}
6. Validate app health and routing.
7. Send ${REPORT_OWNER_NAME} a deployment report using:
   ${EDGE_ROOT_DIR}/bin/report.sh "<title>" "<body>"

## Never publish ports
Do not add "ports:" for apps.
All traffic must go through Traefik + Cloudflare Tunnel.
EOF_POLICY
}

openclaw_require_prereqs() {
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    return 0
  fi

  command_exists git || die "[openclaw] git is required"
  command_exists node || die "[openclaw] node is required"
  command_exists npm || die "[openclaw] npm is required"
}

openclaw_ensure_directories() {
  local runtime_home
  runtime_home="$(openclaw_runtime_home)"

  openclaw_run_root install -d -m 0755 "${OPENCLAW_ROOT_DIR}"
  openclaw_run_root install -d -m 0755 "${OPENCLAW_SOURCE_DIR}"
  openclaw_run_root install -d -m 0755 "${OPENCLAW_NPM_PREFIX}"
  openclaw_run_root install -d -m 0700 "${runtime_home}/.openclaw"
  openclaw_run_root install -d -m 0755 "$(dirname "${OPENCLAW_CONFIG_FILE}")"
  openclaw_run_root install -d -m 0755 "$(dirname "${OPENCLAW_POLICY_FILE}")"
  openclaw_run_root chown -R "${RUNTIME_USER}:${RUNTIME_USER}" "${runtime_home}/.openclaw"
  openclaw_run_root chown -R "${RUNTIME_USER}:${RUNTIME_USER}" "${OPENCLAW_NPM_PREFIX}"
}

openclaw_sync_source_repo() {
  if [[ -d "${OPENCLAW_SOURCE_DIR}/.git" ]]; then
    log_info "[openclaw] updating source repository at ${OPENCLAW_SOURCE_DIR}"
    openclaw_run_root git -C "${OPENCLAW_SOURCE_DIR}" fetch --all --tags
    openclaw_run_root git -C "${OPENCLAW_SOURCE_DIR}" checkout "${OPENCLAW_SOURCE_REF}"
    openclaw_run_root git -C "${OPENCLAW_SOURCE_DIR}" pull --ff-only origin "${OPENCLAW_SOURCE_REF}"
    return 0
  fi

  log_info "[openclaw] cloning source repository"
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    openclaw_run_root git clone --branch "${OPENCLAW_SOURCE_REF}" --depth 1 "${OPENCLAW_SOURCE_REPO}" "${OPENCLAW_SOURCE_DIR}"
    return 0
  fi

  if [[ -d "${OPENCLAW_SOURCE_DIR}" ]]; then
    openclaw_run_root find "${OPENCLAW_SOURCE_DIR}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  fi
  openclaw_run_root git clone --branch "${OPENCLAW_SOURCE_REF}" --depth 1 "${OPENCLAW_SOURCE_REPO}" "${OPENCLAW_SOURCE_DIR}"
}

openclaw_install_cli() {
  log_info "[openclaw] installing OpenClaw CLI (${OPENCLAW_NPM_PACKAGE}@${OPENCLAW_NPM_VERSION}) for ${RUNTIME_USER}"
  # Normalize GitHub git transport to HTTPS so npm git deps do not require SSH keys.
  openclaw_run_as_runtime git config --global url.https://github.com/.insteadOf ssh://git@github.com/
  openclaw_run_as_runtime git config --global --add url.https://github.com/.insteadOf git@github.com:
  openclaw_run_as_runtime npm config set prefix "${OPENCLAW_NPM_PREFIX}"
  openclaw_run_as_runtime npm install -g "${OPENCLAW_NPM_PACKAGE}@${OPENCLAW_NPM_VERSION}"

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    return 0
  fi

  if [[ ! -x "${OPENCLAW_BIN}" ]]; then
    die "[openclaw] expected OpenClaw binary at ${OPENCLAW_BIN} after npm install"
  fi
}

openclaw_write_runtime_files() {
  local config_json
  local env_file
  local policy_file

  config_json="$(openclaw_render_config_json)"
  env_file="$(openclaw_render_env_file)"
  policy_file="$(openclaw_render_policy_agents_md)"

  openclaw_write_content_if_changed "${OPENCLAW_CONFIG_FILE}" "0600" "${config_json}" "${RUNTIME_USER}:${RUNTIME_USER}" || true
  openclaw_write_content_if_changed "$(openclaw_env_file_path)" "0600" "${env_file}" "root:root" || true
  openclaw_write_content_if_changed "${OPENCLAW_POLICY_FILE}" "0644" "${policy_file}" "${RUNTIME_USER}:${RUNTIME_USER}" || true
}

openclaw_fix_runtime_permissions() {
  local runtime_home
  runtime_home="$(openclaw_runtime_home)"

  log_info "[openclaw] ensuring runtime paths are owned by ${RUNTIME_USER}"
  openclaw_run_root install -d -m 0700 -o "${RUNTIME_USER}" -g "${RUNTIME_USER}" "${runtime_home}/.openclaw"
  openclaw_run_root install -d -m 0755 -o "${RUNTIME_USER}" -g "${RUNTIME_USER}" "$(dirname "${OPENCLAW_POLICY_FILE}")"
  openclaw_run_root chown "${RUNTIME_USER}:${RUNTIME_USER}" "${OPENCLAW_CONFIG_FILE}"
  openclaw_run_root chown "${RUNTIME_USER}:${RUNTIME_USER}" "${OPENCLAW_POLICY_FILE}"
  openclaw_run_root chmod 0600 "${OPENCLAW_CONFIG_FILE}"
}

openclaw_write_cli_wrapper() {
  local wrapper_content
  wrapper_content="$(openclaw_render_cli_wrapper)"
  openclaw_write_content_if_changed "$(openclaw_cli_wrapper_path)" "0755" "${wrapper_content}" "root:root" || true
}

openclaw_start_runtime_if_needed() {
  if [[ "${OPENCLAW_START_STACK}" != "true" ]]; then
    return 0
  fi

  if [[ "${OPENCLAW_MANAGE_SYSTEMD}" == "true" ]]; then
    return 0
  fi

  log_warn "[openclaw] OPENCLAW_MANAGE_SYSTEMD=false; skipping automatic gateway start (use systemd or run openclaw gateway manually)."
}

phase_openclaw() {
  if [[ "${OPENCLAW_ENABLE}" != "true" ]]; then
    log_info "[openclaw] OPENCLAW_ENABLE=false; skipping OpenClaw runtime setup"
    return 0
  fi

  if [[ "${OPENCLAW_POLICY_INJECTION}" != "true" ]]; then
    die "[openclaw] OPENCLAW_POLICY_INJECTION must remain true (locked decision)"
  fi

  log_info "[openclaw] configuring OpenClaw runtime"
  if [[ "${OPENCLAW_BUILD_IMAGE}" == "true" ]]; then
    log_info "[openclaw] OPENCLAW_BUILD_IMAGE=true is ignored in host-runtime mode"
  fi
  openclaw_require_prereqs
  openclaw_ensure_directories
  openclaw_sync_source_repo
  openclaw_install_cli
  openclaw_write_runtime_files
  openclaw_fix_runtime_permissions
  openclaw_write_cli_wrapper
  openclaw_start_runtime_if_needed
  log_info "[openclaw] OpenClaw runtime setup complete"
}
