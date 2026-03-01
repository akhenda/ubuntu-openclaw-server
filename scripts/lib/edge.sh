#!/usr/bin/env bash

edge_run_root() {
  if (( EUID == 0 )); then
    run_cmd "$@"
    return 0
  fi

  command_exists sudo || die "[edge] sudo is required when not running as root"
  run_cmd sudo "$@"
}

edge_openclaw_root() {
  printf '%s' "${EDGE_ROOT_DIR}"
}

edge_stack_dir() {
  printf '%s/edge' "$(edge_openclaw_root)"
}

edge_traefik_dir() {
  printf '%s/traefik' "$(edge_stack_dir)"
}

edge_cloudflared_dir() {
  printf '%s/cloudflared' "$(edge_stack_dir)"
}

edge_secrets_dir() {
  printf '%s/secrets' "$(edge_openclaw_root)"
}

edge_compose_file() {
  printf '%s/docker-compose.yml' "$(edge_stack_dir)"
}

edge_traefik_config_file() {
  printf '%s/traefik.yml' "$(edge_traefik_dir)"
}

edge_cloudflared_config_file() {
  printf '%s/config.yml' "$(edge_cloudflared_dir)"
}

edge_cloudflared_credentials_file() {
  if [[ -n "${CLOUDFLARED_CREDENTIALS_FILE:-}" ]]; then
    printf '%s' "${CLOUDFLARED_CREDENTIALS_FILE}"
    return 0
  fi

  printf '%s/%s.json' "$(edge_cloudflared_dir)" "${TUNNEL_UUID}"
}

edge_dashboard_users_file() {
  printf '%s/traefik_dashboard_users.env' "$(edge_secrets_dir)"
}

edge_docker_bin() {
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

edge_require_docker() {
  local docker_cmd="$1"
  if command_exists "${docker_cmd}"; then
    return 0
  fi

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_warn "[edge] docker binary not found; continuing due to --dry-run"
    return 0
  fi

  die "[edge] docker binary not found. Ensure packages phase installed Docker."
}

edge_write_content_if_changed() {
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
    log_info "[edge] no changes for ${target}"
    rm -f "${tmp_file}"
    return 1
  fi

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[edge] [dry-run] would update ${target}"
    rm -f "${tmp_file}"
    return 0
  fi

  edge_run_root install -d -m 0755 "$(dirname "${target}")"
  edge_run_root cp "${tmp_file}" "${target}"
  edge_run_root chown root:root "${target}"
  edge_run_root chmod "${mode}" "${target}"
  rm -f "${tmp_file}"
  return 0
}

edge_ensure_directories() {
  edge_run_root install -d -m 0755 "$(edge_openclaw_root)"
  edge_run_root install -d -m 0755 "$(edge_stack_dir)"
  edge_run_root install -d -m 0755 "$(edge_traefik_dir)"
  edge_run_root install -d -m 0755 "$(edge_cloudflared_dir)"
  edge_run_root install -d -m 0755 "$(edge_secrets_dir)"
}

edge_render_traefik_config() {
  cat <<EOF
providers:
  docker:
    exposedByDefault: false

entryPoints:
  web:
    address: ":80"

api:
  dashboard: true
  insecure: false
EOF
}

edge_render_cloudflared_config() {
  cat <<EOF
tunnel: ${TUNNEL_UUID}
credentials-file: /etc/cloudflared/${TUNNEL_UUID}.json

ingress:
  - hostname: "*.${APPS_DOMAIN}"
    service: http://traefik:80
  - service: http_status:404
EOF
}

edge_render_compose() {
  local dashboard_labels=""
  local dashboard_volume=""

  if [[ -n "${TRAEFIK_DASHBOARD_USERS:-}" ]]; then
    dashboard_volume=$'\n      - '"$(edge_dashboard_users_file):/run/secrets/traefik_dashboard_users.env:ro"
    dashboard_labels=$'\n      - traefik.enable=true'
    dashboard_labels+=$'\n      - traefik.docker.network='"${EDGE_NETWORK_NAME}"
    dashboard_labels+=$'\n      - traefik.http.routers.traefik-dashboard.rule=Host(`'"${TRAEFIK_DASHBOARD_HOST}"'`) && (PathPrefix(`/api`) || PathPrefix(`/dashboard`))'
    dashboard_labels+=$'\n      - traefik.http.routers.traefik-dashboard.entrypoints=web'
    dashboard_labels+=$'\n      - traefik.http.routers.traefik-dashboard.service=api@internal'
    dashboard_labels+=$'\n      - traefik.http.routers.traefik-dashboard.middlewares=traefik-auth'
    dashboard_labels+=$'\n      - traefik.http.middlewares.traefik-auth.basicauth.usersfile=/run/secrets/traefik_dashboard_users.env'
  fi

  cat <<EOF
services:
  traefik:
    image: ${TRAEFIK_IMAGE}
    command:
      - --configFile=/etc/traefik/traefik.yml
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik/traefik.yml:/etc/traefik/traefik.yml:ro${dashboard_volume}
    networks:
      ${EDGE_NETWORK_NAME}:
        ipv4_address: ${TRAEFIK_IP}
    restart: unless-stopped
$( [[ -n "${dashboard_labels}" ]] && printf '    labels:%s\n' "${dashboard_labels}" )

  cloudflared:
    image: ${CLOUDFLARED_IMAGE}
    command: tunnel --no-autoupdate --config /etc/cloudflared/config.yml run
    volumes:
      - ./cloudflared/config.yml:/etc/cloudflared/config.yml:ro
      - ./cloudflared/${TUNNEL_UUID}.json:/etc/cloudflared/${TUNNEL_UUID}.json:ro
    networks:
      ${EDGE_NETWORK_NAME}:
        ipv4_address: ${CLOUDFLARED_IP}
    restart: unless-stopped

networks:
  ${EDGE_NETWORK_NAME}:
    external: true
    name: ${EDGE_NETWORK_NAME}
EOF
}

edge_write_configs() {
  local changed="false"
  local traefik_cfg
  local cloudflared_cfg
  local compose_cfg

  traefik_cfg="$(edge_render_traefik_config)"
  cloudflared_cfg="$(edge_render_cloudflared_config)"
  compose_cfg="$(edge_render_compose)"

  if edge_write_content_if_changed "$(edge_traefik_config_file)" "0644" "${traefik_cfg}"; then
    changed="true"
  fi

  if edge_write_content_if_changed "$(edge_cloudflared_config_file)" "0644" "${cloudflared_cfg}"; then
    changed="true"
  fi

  if edge_write_content_if_changed "$(edge_compose_file)" "0644" "${compose_cfg}"; then
    changed="true"
  fi

  if [[ -n "${TRAEFIK_DASHBOARD_USERS:-}" ]]; then
    local users_content="TRAEFIK_DASH_USERS='${TRAEFIK_DASHBOARD_USERS}'"
    if edge_write_content_if_changed "$(edge_dashboard_users_file)" "0600" "${users_content}"; then
      changed="true"
    fi
  else
    log_warn "[edge] TRAEFIK_DASHBOARD_USERS is empty; Traefik dashboard route will not be published."
  fi

  [[ "${changed}" == "true" ]]
}

edge_ensure_network() {
  local docker_cmd="$1"

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    edge_run_root "${docker_cmd}" network inspect "${EDGE_NETWORK_NAME}"
    edge_run_root "${docker_cmd}" network create --subnet "${EDGE_SUBNET}" "${EDGE_NETWORK_NAME}"
    return 0
  fi

  if edge_run_root "${docker_cmd}" network inspect "${EDGE_NETWORK_NAME}" >/dev/null 2>&1; then
    log_info "[edge] docker network '${EDGE_NETWORK_NAME}' already exists"
    return 0
  fi

  log_info "[edge] creating docker network '${EDGE_NETWORK_NAME}' (${EDGE_SUBNET})"
  edge_run_root "${docker_cmd}" network create --subnet "${EDGE_SUBNET}" "${EDGE_NETWORK_NAME}"
}

edge_start_stack() {
  local docker_cmd="$1"
  local creds_file
  creds_file="$(edge_cloudflared_credentials_file)"

  if [[ "${EDGE_REQUIRE_TUNNEL_CREDENTIALS}" == "true" && ! -f "${creds_file}" ]]; then
    log_warn "[edge] cloudflared credentials not found at ${creds_file}; skipping stack start."
    return 0
  fi

  local compose_file
  compose_file="$(edge_compose_file)"
  edge_run_root "${docker_cmd}" compose -f "${compose_file}" up -d

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[edge] [dry-run] would show edge stack status"
  else
    edge_run_root "${docker_cmd}" compose -f "${compose_file}" ps
  fi
}

phase_edge() {
  if [[ "${EDGE_ENABLE}" != "true" ]]; then
    log_info "[edge] EDGE_ENABLE=false; skipping edge stack configuration"
    return 0
  fi

  log_info "[edge] configuring edge stack"

  local docker_cmd
  docker_cmd="$(edge_docker_bin)"
  edge_require_docker "${docker_cmd}"

  edge_ensure_directories
  edge_write_configs || true
  edge_ensure_network "${docker_cmd}"

  if [[ "${EDGE_START_STACK}" == "true" ]]; then
    edge_start_stack "${docker_cmd}"
  else
    log_info "[edge] EDGE_START_STACK=false; skipping compose up"
  fi

  log_info "[edge] edge stack configuration complete"
}
