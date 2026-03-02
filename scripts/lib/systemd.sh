#!/usr/bin/env bash

systemd_run_root() {
  if (( EUID == 0 )); then
    run_cmd "$@"
    return $?
  fi

  command_exists sudo || die "[systemd] sudo is required when not running as root"
  run_cmd sudo "$@"
}

systemd_write_content_if_changed() {
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
    log_info "[systemd] no changes for ${target}"
    rm -f "${tmp_file}"
    return 1
  fi

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[systemd] [dry-run] would update ${target}"
    rm -f "${tmp_file}"
    return 0
  fi

  systemd_run_root install -d -m 0755 "$(dirname "${target}")"
  systemd_run_root cp "${tmp_file}" "${target}"
  systemd_run_root chown root:root "${target}"
  systemd_run_root chmod "${mode}" "${target}"
  rm -f "${tmp_file}"
  return 0
}

systemd_render_edge_unit() {
  cat <<EOF
[Unit]
Description=OpenClaw Edge Stack (Traefik + cloudflared)
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${EDGE_ROOT_DIR}/edge
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
}

systemd_render_openclaw_unit() {
  cat <<EOF
[Unit]
Description=OpenClaw Gateway (Host Runtime)
After=docker.service openclaw-edge.service
Requires=docker.service openclaw-edge.service

[Service]
Type=simple
User=${RUNTIME_USER}
Group=${RUNTIME_USER}
SupplementaryGroups=docker
EnvironmentFile=-${OPENCLAW_ROOT_DIR}/.env
Environment=HOME=${OPENCLAW_RUNTIME_HOME}
Environment=PATH=${OPENCLAW_NPM_PREFIX}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
WorkingDirectory=${OPENCLAW_ROOT_DIR}
ExecStart=${OPENCLAW_BIN} gateway --bind ${OPENCLAW_GATEWAY_BIND} --port ${OPENCLAW_GATEWAY_PORT}
Restart=always
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
}

systemd_render_apps_unit() {
  cat <<EOF
[Unit]
Description=OpenClaw Apps Stack (Docker)
After=docker.service openclaw-edge.service
Requires=docker.service openclaw-edge.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${APPS_ROOT_DIR}
ExecStart=/usr/bin/docker compose -f ${APPS_COMPOSE_FILE} up -d
ExecStop=/usr/bin/docker compose -f ${APPS_COMPOSE_FILE} down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
}

systemd_write_unit_if_enabled() {
  local enabled_flag="$1"
  local unit_file="$2"
  local content="$3"
  local changed_ref="$4"

  if [[ "${enabled_flag}" != "true" ]]; then
    return 0
  fi

  if systemd_write_content_if_changed "${unit_file}" "0644" "${content}"; then
    printf -v "${changed_ref}" '%s' "true"
  fi
}

systemd_enable_unit_if_enabled() {
  local enabled_flag="$1"
  local start_flag="$2"
  local unit_file="$3"

  if [[ "${enabled_flag}" != "true" ]]; then
    return 0
  fi

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    if [[ "${start_flag}" == "true" ]]; then
      systemd_run_root systemctl enable --now "$(basename "${unit_file}")"
    else
      systemd_run_root systemctl enable "$(basename "${unit_file}")"
    fi
    return 0
  fi

  if ! command_exists systemctl; then
    log_warn "[systemd] systemctl not available; skipping enable/start for $(basename "${unit_file}")"
    return 0
  fi

  if [[ "${start_flag}" == "true" ]]; then
    systemd_run_root systemctl enable --now "$(basename "${unit_file}")"
  else
    systemd_run_root systemctl enable "$(basename "${unit_file}")"
  fi
}

phase_systemd() {
  log_info "[systemd] managing stack lifecycle units"

  local changed_any="false"

  if [[ "${EDGE_ENABLE}" == "true" ]]; then
    local edge_unit
    edge_unit="$(systemd_render_edge_unit)"
    systemd_write_unit_if_enabled "${EDGE_MANAGE_SYSTEMD}" "${EDGE_SYSTEMD_UNIT}" "${edge_unit}" changed_any
  fi

  if [[ "${OPENCLAW_ENABLE}" == "true" ]]; then
    local openclaw_unit
    openclaw_unit="$(systemd_render_openclaw_unit)"
    systemd_write_unit_if_enabled "${OPENCLAW_MANAGE_SYSTEMD}" "${OPENCLAW_SYSTEMD_UNIT}" "${openclaw_unit}" changed_any
  fi

  if [[ "${APPS_ENABLE}" == "true" ]]; then
    local apps_unit
    apps_unit="$(systemd_render_apps_unit)"
    systemd_write_unit_if_enabled "${APPS_MANAGE_SYSTEMD}" "${APPS_SYSTEMD_UNIT}" "${apps_unit}" changed_any
  fi

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    systemd_run_root systemctl daemon-reload
  elif [[ "${changed_any}" == "true" ]]; then
    if command_exists systemctl; then
      systemd_run_root systemctl daemon-reload
    else
      log_warn "[systemd] systemctl not available; skipping daemon-reload"
    fi
  fi

  if [[ "${EDGE_ENABLE}" == "true" ]]; then
    systemd_enable_unit_if_enabled "${EDGE_MANAGE_SYSTEMD}" "${EDGE_START_STACK}" "${EDGE_SYSTEMD_UNIT}"
  fi
  if [[ "${OPENCLAW_ENABLE}" == "true" ]]; then
    systemd_enable_unit_if_enabled "${OPENCLAW_MANAGE_SYSTEMD}" "${OPENCLAW_START_STACK}" "${OPENCLAW_SYSTEMD_UNIT}"
  fi
  if [[ "${APPS_ENABLE}" == "true" ]]; then
    systemd_enable_unit_if_enabled "${APPS_MANAGE_SYSTEMD}" "${APPS_START_STACK}" "${APPS_SYSTEMD_UNIT}"
  fi

  log_info "[systemd] stack lifecycle unit management complete"
}
