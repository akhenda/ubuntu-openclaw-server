#!/usr/bin/env bash

motd_run_root() {
  if (( EUID == 0 )); then
    run_cmd "$@"
    return $?
  fi

  command_exists sudo || die "[motd] sudo is required when not running as root"
  run_cmd sudo "$@"
}

motd_write_content_if_changed() {
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
    log_info "[motd] no changes for ${target}"
    rm -f "${tmp_file}"
    return 1
  fi

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[motd] [dry-run] would update ${target}"
    rm -f "${tmp_file}"
    return 0
  fi

  motd_run_root install -d -m 0755 "$(dirname "${target}")"
  motd_run_root cp "${tmp_file}" "${target}"
  motd_run_root chown root:root "${target}"
  motd_run_root chmod "${mode}" "${target}"
  rm -f "${tmp_file}"
  return 0
}

motd_render_script() {
  cat <<EOF
#!/usr/bin/env bash
set +e

printf '\n'
printf 'OpenClaw Host Status (%s)\n' "\$(date -u +'%Y-%m-%d %H:%M:%SZ')"
printf '========================================\n'

if command -v systemctl >/dev/null 2>&1; then
  docker_state="\$(systemctl is-active docker 2>/dev/null || true)"
  fail2ban_state="\$(systemctl is-active fail2ban 2>/dev/null || true)"
  openclaw_state="\$(systemctl is-active openclaw-gateway 2>/dev/null || true)"
else
  docker_state="unknown"
  fail2ban_state="unknown"
  openclaw_state="unknown"
fi

if command -v docker >/dev/null 2>&1; then
  app_count="\$(docker ps --format '{{.Names}}' 2>/dev/null | wc -l | tr -d ' ')"
else
  app_count="0"
fi

uptime_text="\$(uptime -p 2>/dev/null || true)"
ram_text="\$(free -h 2>/dev/null | awk '/Mem:/ {print \$3\"/\"\$2}' || true)"
disk_text="\$(df -h / 2>/dev/null | awk 'NR==2 {print \$3\"/\"\$2\" (\"\$5\")\"}' || true)"
pub_ip="\$(curl -fsS --max-time 2 https://api.ipify.org 2>/dev/null || echo 'unavailable')"

printf 'Docker:               %s\n' "\${docker_state:-unknown}"
printf 'OpenClaw Gateway:     %s\n' "\${openclaw_state:-unknown}"
printf 'Running Containers:   %s\n' "\${app_count:-0}"
printf 'Fail2ban:             %s\n' "\${fail2ban_state:-unknown}"
printf 'Uptime:               %s\n' "\${uptime_text:-unknown}"
printf 'RAM Usage:            %s\n' "\${ram_text:-unknown}"
printf 'Disk Usage (/):       %s\n' "\${disk_text:-unknown}"
printf 'Public IP:            %s\n' "\${pub_ip:-unavailable}"
printf '\n'
printf 'Security Notices:\n'
printf '- SSH: port ${SSH_PORT}, root login disabled, password auth disabled\n'
printf '- Firewall: ufw baseline policy (deny incoming / allow outgoing)\n'
printf '- Updates: unattended-upgrades enabled\n'
printf '\n'
EOF
}

phase_motd() {
  if [[ "${MOTD_ENABLE}" != "true" ]]; then
    log_info "[motd] MOTD_ENABLE=false; skipping MOTD setup"
    return 0
  fi

  log_info "[motd] configuring dynamic MOTD status script"

  local script_content
  script_content="$(motd_render_script)"
  motd_write_content_if_changed "${MOTD_SCRIPT_PATH}" "0755" "${script_content}" || true

  log_info "[motd] MOTD setup complete"
}
