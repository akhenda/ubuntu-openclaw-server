#!/usr/bin/env bash

openclaw_run_root() {
  if (( EUID == 0 )); then
    run_cmd "$@"
    return $?
  fi

  command_exists sudo || die "[openclaw] sudo is required when not running as root"
  run_cmd sudo "$@"
}

openclaw_docker_bin() {
  if [[ -n "${DOCKER_BIN:-}" ]]; then
    printf '%s' "${DOCKER_BIN}"
    return 0
  fi

  if command_exists docker; then
    command -v docker
    return 0
  fi

  printf '%s' "docker"
}

openclaw_write_content_if_changed() {
  local target="$1"
  local mode="$2"
  local content="$3"

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
  openclaw_run_root chown root:root "${target}"
  openclaw_run_root chmod "${mode}" "${target}"
  rm -f "${tmp_file}"
  return 0
}

openclaw_env_file_path() {
  printf '%s/.env' "${OPENCLAW_ROOT_DIR}"
}

openclaw_compose_file_path() {
  printf '%s/docker-compose.yml' "${OPENCLAW_ROOT_DIR}"
}

openclaw_workspace_root() {
  printf '%s/workspace' "${OPENCLAW_ROOT_DIR}"
}

openclaw_config_root() {
  printf '%s/config' "${OPENCLAW_ROOT_DIR}"
}

openclaw_render_config_json() {
  cat <<EOF
{
  "agents": {
    "defaults": {
      "workspace": "/home/node/.openclaw/workspace"
    }
  },
  "gateway": {
    "trustedProxies": ["${TRAEFIK_IP}"],
    "allowRealIpFallback": false,
    "auth": {
      "mode": "password",
      "password": "${OPENCLAW_GATEWAY_PASSWORD}"
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
EOF
}

openclaw_render_env_file() {
  cat <<EOF
OPENCLAW_IMAGE=${OPENCLAW_IMAGE}
OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
OPENCLAW_GATEWAY_PASSWORD=${OPENCLAW_GATEWAY_PASSWORD}
BOT_NAME=${BOT_NAME}
APPS_DOMAIN=${APPS_DOMAIN}
EOF
}

openclaw_render_compose_file() {
  cat <<EOF
services:
  openclaw-gateway:
    image: \${OPENCLAW_IMAGE:-openclaw:local}
    environment:
      HOME: /home/node
      TERM: xterm-256color
      OPENCLAW_GATEWAY_TOKEN: \${OPENCLAW_GATEWAY_TOKEN}
      OPENCLAW_GATEWAY_PASSWORD: \${OPENCLAW_GATEWAY_PASSWORD}
    volumes:
      - ${OPENCLAW_ROOT_DIR}/config:/home/node/.openclaw
      - ${OPENCLAW_ROOT_DIR}/workspace:/home/node/.openclaw/workspace
    init: true
    restart: unless-stopped
    command: ["node","dist/index.js","gateway","--bind","lan","--port","${OPENCLAW_GATEWAY_PORT}"]
    networks:
      ${EDGE_NETWORK_NAME}:
        ipv4_address: ${OPENCLAW_GATEWAY_IP}
    labels:
      - traefik.enable=true
      - traefik.docker.network=${EDGE_NETWORK_NAME}
      - traefik.http.routers.openclaw.rule=Host(\`${BOT_NAME}.${APPS_DOMAIN}\`)
      - traefik.http.routers.openclaw.entrypoints=web
      - traefik.http.services.openclaw.loadbalancer.server.port=${OPENCLAW_GATEWAY_PORT}

  openclaw-cli:
    image: \${OPENCLAW_IMAGE:-openclaw:local}
    environment:
      HOME: /home/node
      TERM: xterm-256color
      OPENCLAW_GATEWAY_TOKEN: \${OPENCLAW_GATEWAY_TOKEN}
      OPENCLAW_GATEWAY_PASSWORD: \${OPENCLAW_GATEWAY_PASSWORD}
      BROWSER: "echo"
    volumes:
      - ${OPENCLAW_ROOT_DIR}/config:/home/node/.openclaw
      - ${OPENCLAW_ROOT_DIR}/workspace:/home/node/.openclaw/workspace
    stdin_open: true
    tty: true
    init: true
    entrypoint: ["node","dist/index.js"]
    networks:
      - ${EDGE_NETWORK_NAME}

networks:
  ${EDGE_NETWORK_NAME}:
    external: true
    name: ${EDGE_NETWORK_NAME}
EOF
}

openclaw_render_policy_agents_md() {
  cat <<EOF
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
EOF
}

openclaw_render_systemd_unit() {
  cat <<EOF
[Unit]
Description=OpenClaw Gateway (Docker)
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${OPENCLAW_ROOT_DIR}
ExecStart=/usr/bin/docker compose --env-file .env up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
}

openclaw_require_prereqs() {
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    return 0
  fi

  command_exists git || die "[openclaw] git is required"
}

openclaw_ensure_directories() {
  openclaw_run_root install -d -m 0755 "${OPENCLAW_ROOT_DIR}"
  openclaw_run_root install -d -m 0755 "${OPENCLAW_SOURCE_DIR}"
  openclaw_run_root install -d -m 0755 "$(openclaw_config_root)"
  openclaw_run_root install -d -m 0755 "$(openclaw_workspace_root)"
  openclaw_run_root install -d -m 0755 "$(dirname "${OPENCLAW_POLICY_FILE}")"
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

openclaw_build_image_if_enabled() {
  if [[ "${OPENCLAW_BUILD_IMAGE}" != "true" ]]; then
    log_info "[openclaw] OPENCLAW_BUILD_IMAGE=false; skipping docker build"
    return 0
  fi

  local docker_cmd
  docker_cmd="$(openclaw_docker_bin)"
  if [[ "${DRY_RUN:-false}" != "true" ]] && ! command_exists "${docker_cmd}"; then
    die "[openclaw] docker binary not found"
  fi

  openclaw_run_root "${docker_cmd}" build -t "${OPENCLAW_IMAGE}" -f "${OPENCLAW_SOURCE_DIR}/Dockerfile" "${OPENCLAW_SOURCE_DIR}"
}

openclaw_write_runtime_files() {
  local config_json
  local env_file
  local compose_file
  local policy_file

  config_json="$(openclaw_render_config_json)"
  env_file="$(openclaw_render_env_file)"
  compose_file="$(openclaw_render_compose_file)"
  policy_file="$(openclaw_render_policy_agents_md)"

  openclaw_write_content_if_changed "${OPENCLAW_CONFIG_FILE}" "0600" "${config_json}" || true
  openclaw_write_content_if_changed "$(openclaw_env_file_path)" "0600" "${env_file}" || true
  openclaw_write_content_if_changed "$(openclaw_compose_file_path)" "0644" "${compose_file}" || true
  openclaw_write_content_if_changed "${OPENCLAW_POLICY_FILE}" "0644" "${policy_file}" || true
}

openclaw_write_systemd_unit_if_enabled() {
  if [[ "${OPENCLAW_MANAGE_SYSTEMD}" != "true" ]]; then
    log_info "[openclaw] OPENCLAW_MANAGE_SYSTEMD=false; skipping systemd unit management"
    return 0
  fi

  local unit_content
  unit_content="$(openclaw_render_systemd_unit)"
  openclaw_write_content_if_changed "${OPENCLAW_SYSTEMD_UNIT}" "0644" "${unit_content}" || true

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    openclaw_run_root systemctl daemon-reload
    if [[ "${OPENCLAW_START_STACK}" == "true" ]]; then
      openclaw_run_root systemctl enable --now "$(basename "${OPENCLAW_SYSTEMD_UNIT}")"
    else
      openclaw_run_root systemctl enable "$(basename "${OPENCLAW_SYSTEMD_UNIT}")"
    fi
    return 0
  fi

  if command_exists systemctl; then
    openclaw_run_root systemctl daemon-reload
    if [[ "${OPENCLAW_START_STACK}" == "true" ]]; then
      openclaw_run_root systemctl enable --now "$(basename "${OPENCLAW_SYSTEMD_UNIT}")"
    else
      openclaw_run_root systemctl enable "$(basename "${OPENCLAW_SYSTEMD_UNIT}")"
    fi
    return 0
  fi

  log_warn "[openclaw] systemctl not available; cannot manage ${OPENCLAW_SYSTEMD_UNIT}"
}

openclaw_start_compose_direct_if_needed() {
  if [[ "${OPENCLAW_START_STACK}" != "true" ]]; then
    return 0
  fi

  if [[ "${OPENCLAW_MANAGE_SYSTEMD}" == "true" ]]; then
    return 0
  fi

  local docker_cmd
  docker_cmd="$(openclaw_docker_bin)"
  openclaw_run_root "${docker_cmd}" compose -f "$(openclaw_compose_file_path)" --env-file "$(openclaw_env_file_path)" up -d
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
  openclaw_require_prereqs
  openclaw_ensure_directories
  openclaw_sync_source_repo
  openclaw_build_image_if_enabled
  openclaw_write_runtime_files
  openclaw_start_compose_direct_if_needed
  log_info "[openclaw] OpenClaw runtime setup complete"
}
