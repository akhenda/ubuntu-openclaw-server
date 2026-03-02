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

openclaw_write_content_if_missing() {
  local target="$1"
  local mode="$2"
  local content="$3"
  local owner="${4:-root:root}"

  if [[ -f "${target}" ]]; then
    log_info "[openclaw] keeping existing ${target}"
    return 1
  fi

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[openclaw] [dry-run] would create ${target}"
    return 0
  fi

  local tmp_file
  tmp_file="$(mktemp)"
  printf '%s\n' "${content}" > "${tmp_file}"
  openclaw_run_root install -d -m 0755 "$(dirname "${target}")"
  openclaw_run_root cp "${tmp_file}" "${target}"
  openclaw_run_root chown "${owner}" "${target}"
  openclaw_run_root chmod "${mode}" "${target}"
  rm -f "${tmp_file}"
  return 0
}

openclaw_repo_root() {
  if [[ -n "${REPO_ROOT:-}" ]]; then
    printf '%s' "${REPO_ROOT}"
    return 0
  fi

  local lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  printf '%s' "${lib_dir}"
}

openclaw_read_repo_template() {
  local relative_path="$1"
  local root
  root="$(openclaw_repo_root)"
  local template_path="${root}/${relative_path}"
  [[ -f "${template_path}" ]] || die "[openclaw] template not found: ${template_path}"
  cat "${template_path}"
}

openclaw_merge_config_json_with_existing() {
  local desired_json="$1"

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    printf '%s' "${desired_json}"
    return 0
  fi

  if [[ ! -f "${OPENCLAW_CONFIG_FILE}" ]]; then
    printf '%s' "${desired_json}"
    return 0
  fi

  local existing_json
  if ! existing_json="$(cat "${OPENCLAW_CONFIG_FILE}" 2>/dev/null)"; then
    printf '%s' "${desired_json}"
    return 0
  fi

  local merged_json
  if ! merged_json="$(jq -n \
    --argjson existing "${existing_json}" \
    --argjson desired "${desired_json}" '
      def merge(a; b):
        if (a | type) == "object" and (b | type) == "object" then
          reduce (((a | keys_unsorted) + (b | keys_unsorted) | unique)[]) as $k
            ({};
              .[$k] = merge(a[$k]; b[$k])
            )
        elif b == null then a
        else b
        end;
      merge($existing; $desired)
    ' 2>/dev/null)"; then
    log_warn "[openclaw] existing config merge failed; using desired baseline"
    printf '%s' "${desired_json}"
    return 0
  fi

  printf '%s' "${merged_json}"
}

openclaw_env_file_path() {
  printf '%s/.env' "${OPENCLAW_ROOT_DIR}"
}

openclaw_cli_wrapper_path() {
  printf '%s' "/usr/local/bin/openclaw"
}

openclaw_workspace_publish_script_path() {
  local runtime_home
  runtime_home="$(openclaw_runtime_home)"
  printf '%s/.openclaw/workspace/policies/deploy/publish_workspace_app.sh' "${runtime_home}"
}

openclaw_workspace_app_builder_policy_path() {
  local runtime_home
  runtime_home="$(openclaw_runtime_home)"
  printf '%s/.openclaw/workspace/policies/deploy/APP_BUILDER.md' "${runtime_home}"
}

openclaw_workspace_skill_app_builder_path() {
  local runtime_home
  runtime_home="$(openclaw_runtime_home)"
  printf '%s/.openclaw/skills/app_builder/SKILL.md' "${runtime_home}"
}

openclaw_host_definition_of_done_path() {
  printf '%s/AGENTS.md' "${EDGE_ROOT_DIR}"
}

openclaw_host_global_compose_template_path() {
  printf '%s/infra/global-compose/docker-compose.yml' "${EDGE_ROOT_DIR}"
}

openclaw_host_global_compose_env_template_path() {
  printf '%s/infra/global-compose/.env' "${EDGE_ROOT_DIR}"
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
          "paths": ["policies/deploy/AGENTS.md", "policies/deploy/APP_BUILDER.md"]
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
OPENCLAW_ENV_FILE="${OPENCLAW_ROOT_DIR}/.env"

load_runtime_env() {
  if [[ -r "\${OPENCLAW_ENV_FILE}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "\${OPENCLAW_ENV_FILE}"
    set +a
  fi
}

if [[ ! -x "\${OPENCLAW_BIN}" ]]; then
  echo "OpenClaw binary not found at \${OPENCLAW_BIN}." >&2
  echo "Run the installer first: make run-install" >&2
  exit 1
fi

if [[ "\${USER:-}" == "\${RUNTIME_USER}" ]]; then
  load_runtime_env
  exec env \
    HOME="\${RUNTIME_HOME}" \
    PATH="\${OPENCLAW_PATH}" \
    OPENCLAW_GATEWAY_TOKEN="\${OPENCLAW_GATEWAY_TOKEN:-}" \
    OPENCLAW_GATEWAY_PASSWORD="\${OPENCLAW_GATEWAY_PASSWORD:-}" \
    OPENCLAW_GATEWAY_PORT="\${OPENCLAW_GATEWAY_PORT:-}" \
    OPENCLAW_CONFIG_FILE="\${OPENCLAW_CONFIG_FILE:-}" \
    "\${OPENCLAW_BIN}" "\$@"
fi

if ! command -v sudo >/dev/null 2>&1; then
  echo "sudo is required to run OpenClaw as \${RUNTIME_USER}." >&2
  exit 1
fi

load_runtime_env
exec sudo -u "\${RUNTIME_USER}" -H env \
  HOME="\${RUNTIME_HOME}" \
  PATH="\${OPENCLAW_PATH}" \
  OPENCLAW_GATEWAY_TOKEN="\${OPENCLAW_GATEWAY_TOKEN:-}" \
  OPENCLAW_GATEWAY_PASSWORD="\${OPENCLAW_GATEWAY_PASSWORD:-}" \
  OPENCLAW_GATEWAY_PORT="\${OPENCLAW_GATEWAY_PORT:-}" \
  OPENCLAW_CONFIG_FILE="\${OPENCLAW_CONFIG_FILE:-}" \
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
  local runtime_home
  runtime_home="$(openclaw_runtime_home)"

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

1. Create the project directory INSIDE YOUR WORKSPACE:
   ${runtime_home}/.openclaw/workspace/<appName>/
2. Add a Dockerfile (and any required source files) so the app can build from that workspace folder.
3. Determine the internal app port (for example 3000).
4. Publish workspace app + deploy using:
   ${runtime_home}/.openclaw/workspace/policies/deploy/publish_workspace_app.sh <appName> <port>
5. Hub routing is mandatory:
   - Ensure hub exists at https://${HUB_PRIMARY_HOST}
   - App cards must resolve to https://<appName>.${APPS_DOMAIN}
6. Validate app health and routing.
7. Send ${REPORT_OWNER_NAME} a deployment report using:
   ${EDGE_ROOT_DIR}/bin/report.sh "<title>" "<body>"

## Never ask operator for manual copy unless publish script fails
Do not ask the operator to manually copy app files from workspace to /opt paths unless:
- publish_workspace_app.sh fails, and
- you include the exact failing error first.

## Runtime preflight is mandatory
Before any deploy action, determine whether host exec is available.
- If host exec is unavailable (direct sandbox runtime):
  - You MAY scaffold files in workspace.
  - You MUST NOT claim deployment succeeded.
  - You MUST ask operator to run exactly:
    ${runtime_home}/.openclaw/workspace/policies/deploy/publish_workspace_app.sh <appName> <port>
- If host exec is available:
  - You MUST run publish_workspace_app.sh yourself.

## Definition of done
An app task is DONE only if:
1. Project exists in workspace: ${runtime_home}/.openclaw/workspace/<appName>
2. Dockerization exists (Dockerfile + .dockerignore as needed)
3. Deploy command completed:
   ${runtime_home}/.openclaw/workspace/policies/deploy/publish_workspace_app.sh <appName> <port>
4. App container is up in ${APPS_COMPOSE_FILE}
5. URL responds: https://<appName>.${APPS_DOMAIN}
6. Report includes:
   - repo/app path
   - deploy command used
   - test/build commands + outcome
   - URL + healthcheck result
   - logs command: docker logs -f <container>

## Never publish ports
Do not add "ports:" for apps.
All traffic must go through Traefik + Cloudflare Tunnel.
EOF_POLICY
}

openclaw_render_app_builder_policy_md() {
  local runtime_home
  runtime_home="$(openclaw_runtime_home)"

  cat <<EOF_APP_BUILDER
# App Builder Policy (OpenClaw Host Contract)

Use this policy when building, testing, and deploying apps for this host.

## Canonical paths
- Workspace root: ${runtime_home}/.openclaw/workspace
- Deploy policy: ${runtime_home}/.openclaw/workspace/policies/deploy/AGENTS.md
- Publish helper: ${runtime_home}/.openclaw/workspace/policies/deploy/publish_workspace_app.sh
- Apps compose: ${APPS_COMPOSE_FILE}
- Edge stack (do not modify for app deploys): ${EDGE_ROOT_DIR}/edge/docker-compose.yml

## Standard workflow
1. Create or update app in: ${runtime_home}/.openclaw/workspace/<appName>
2. Ensure Dockerfile and runtime command bind to 0.0.0.0 on internal app port.
3. Run build/tests in workspace first.
4. Deploy using publish helper:
   ${runtime_home}/.openclaw/workspace/policies/deploy/publish_workspace_app.sh <appName> <port>
5. Verify:
   - docker compose -f ${APPS_COMPOSE_FILE} ps
   - curl -I https://<appName>.${APPS_DOMAIN}
6. Report concise outcome and exact commands.

## Runtime boundary rule
If running in direct sandbox runtime (no host exec), do not pretend deployment happened.
Return the single operator command required to deploy on host.

## Required response format
### Summary
- app name
- workspace path
- deployment status
- URL

### Checks
- build/test commands run
- healthcheck result

### Ops
- container/log commands
- any DNS/proxy issue if observed
EOF_APP_BUILDER
}

openclaw_render_global_compose_env() {
  cat <<EOF_GLOBAL_COMPOSE_ENV
BASE_DOMAIN=${APPS_DOMAIN}
ACME_EMAIL=admin@${DOMAIN}
BOT_NAME=${BOT_NAME}
EOF_GLOBAL_COMPOSE_ENV
}

openclaw_render_workspace_publish_script() {
  local runtime_home
  runtime_home="$(openclaw_runtime_home)"

  cat <<EOF_PUBLISH
#!/usr/bin/env bash
set -euo pipefail

APP_NAME="\${1:?app name required}"
APP_PORT="\${2:?internal port required (e.g. 3000)}"

WORKSPACE_ROOT="${runtime_home}/.openclaw/workspace"
SRC_DIR="\${WORKSPACE_ROOT}/\${APP_NAME}"
DEST_ROOT="${APPS_ROOT_DIR}"
DEST_DIR="\${DEST_ROOT}/\${APP_NAME}"
DEPLOY_SCRIPT="${APPS_DEPLOY_SCRIPT}"

if [[ ! -d "\${SRC_DIR}" ]]; then
  echo "Source app directory not found: \${SRC_DIR}" >&2
  exit 1
fi

if [[ ! -x "\${DEPLOY_SCRIPT}" ]]; then
  echo "Deploy script not executable: \${DEPLOY_SCRIPT}" >&2
  exit 1
fi

mkdir -p "\${DEST_DIR}"

if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete \
    --exclude ".git" \
    --exclude "node_modules" \
    --exclude ".next" \
    --exclude "dist" \
    --exclude "build" \
    "\${SRC_DIR}/" "\${DEST_DIR}/"
else
  rm -rf "\${DEST_DIR}"
  mkdir -p "\${DEST_DIR}"
  cp -a "\${SRC_DIR}/." "\${DEST_DIR}/"
fi

"\${DEPLOY_SCRIPT}" "\${APP_NAME}" "\${APP_PORT}"
EOF_PUBLISH
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
  openclaw_run_as_runtime git config --global --unset-all url.https://github.com/.insteadOf || true
  openclaw_run_as_runtime git config --global --add url.https://github.com/.insteadOf ssh://git@github.com/
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
  local app_builder_policy_file
  local publish_script
  local app_builder_skill
  local definition_of_done
  local global_compose_template
  local global_compose_env

  config_json="$(openclaw_render_config_json)"
  config_json="$(openclaw_merge_config_json_with_existing "${config_json}")"
  env_file="$(openclaw_render_env_file)"
  policy_file="$(openclaw_render_policy_agents_md)"
  app_builder_policy_file="$(openclaw_render_app_builder_policy_md)"
  publish_script="$(openclaw_render_workspace_publish_script)"
  app_builder_skill="$(openclaw_read_repo_template "skills/app_builder/SKILL.md")"
  definition_of_done="$(openclaw_read_repo_template "skills/app_builder/templates/AGENTS.md")"
  global_compose_template="$(openclaw_read_repo_template "skills/app_builder/templates/global-compose/docker-compose.yml")"
  global_compose_env="$(openclaw_render_global_compose_env)"

  openclaw_write_content_if_changed "${OPENCLAW_CONFIG_FILE}" "0600" "${config_json}" "${RUNTIME_USER}:${RUNTIME_USER}" || true
  openclaw_write_content_if_changed "$(openclaw_env_file_path)" "0640" "${env_file}" "root:${RUNTIME_USER}" || true
  openclaw_write_content_if_changed "${OPENCLAW_POLICY_FILE}" "0644" "${policy_file}" "${RUNTIME_USER}:${RUNTIME_USER}" || true
  openclaw_write_content_if_changed "$(openclaw_workspace_app_builder_policy_path)" "0644" "${app_builder_policy_file}" "${RUNTIME_USER}:${RUNTIME_USER}" || true
  openclaw_write_content_if_changed "$(openclaw_workspace_publish_script_path)" "0755" "${publish_script}" "${RUNTIME_USER}:${RUNTIME_USER}" || true
  openclaw_write_content_if_changed "$(openclaw_workspace_skill_app_builder_path)" "0644" "${app_builder_skill}" "${RUNTIME_USER}:${RUNTIME_USER}" || true
  openclaw_write_content_if_missing "$(openclaw_host_definition_of_done_path)" "0644" "${definition_of_done}" "root:root" || true
  openclaw_write_content_if_missing "$(openclaw_host_global_compose_template_path)" "0644" "${global_compose_template}" "root:root" || true
  openclaw_write_content_if_missing "$(openclaw_host_global_compose_env_template_path)" "0644" "${global_compose_env}" "root:root" || true
}

openclaw_fix_runtime_permissions() {
  local runtime_home
  runtime_home="$(openclaw_runtime_home)"

  log_info "[openclaw] ensuring runtime paths are owned by ${RUNTIME_USER}"
  openclaw_run_root install -d -m 0700 -o "${RUNTIME_USER}" -g "${RUNTIME_USER}" "${runtime_home}/.openclaw"
  openclaw_run_root install -d -m 0755 -o "${RUNTIME_USER}" -g "${RUNTIME_USER}" "$(dirname "${OPENCLAW_POLICY_FILE}")"
  openclaw_run_root chown "root:${RUNTIME_USER}" "$(openclaw_env_file_path)"
  openclaw_run_root chmod 0640 "$(openclaw_env_file_path)"
  openclaw_run_root chown "${RUNTIME_USER}:${RUNTIME_USER}" "${OPENCLAW_CONFIG_FILE}"
  openclaw_run_root chown "${RUNTIME_USER}:${RUNTIME_USER}" "${OPENCLAW_POLICY_FILE}"
  openclaw_run_root chown "${RUNTIME_USER}:${RUNTIME_USER}" "$(openclaw_workspace_app_builder_policy_path)"
  openclaw_run_root chown "${RUNTIME_USER}:${RUNTIME_USER}" "$(openclaw_workspace_publish_script_path)"
  openclaw_run_root chown "${RUNTIME_USER}:${RUNTIME_USER}" "$(openclaw_workspace_skill_app_builder_path)"
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
