#!/usr/bin/env bash

system_run_root() {
  if (( EUID == 0 )); then
    run_cmd "$@"
    return $?
  fi

  command_exists sudo || die "[system] sudo is required when not running as root"
  run_cmd sudo "$@"
}

system_write_content_if_changed() {
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
    log_info "[system] no changes for ${target}"
    rm -f "${tmp_file}"
    return 1
  fi

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[system] [dry-run] would update ${target}"
    rm -f "${tmp_file}"
    return 0
  fi

  system_run_root install -d -m 0755 "$(dirname "${target}")"
  system_run_root cp "${tmp_file}" "${target}"
  system_run_root chown root:root "${target}"
  system_run_root chmod "${mode}" "${target}"
  rm -f "${tmp_file}"
  return 0
}

system_detect_host_ip() {
  if [[ -n "${HOST_IP:-}" ]]; then
    printf '%s' "${HOST_IP}"
    return 0
  fi

  if command_exists ip; then
    local detected
    detected="$(ip route get 1.1.1.1 2>/dev/null | awk '/src/ {print $7; exit}')"
    if [[ -n "${detected}" ]]; then
      printf '%s' "${detected}"
      return 0
    fi
  fi

  if command_exists hostname; then
    hostname -I 2>/dev/null | awk '{print $1}'
    return 0
  fi

  printf '%s' "127.0.0.1"
}

system_configure_hostname() {
  local host_short="${HOST_FQDN%%.*}"
  local host_ip
  host_ip="$(system_detect_host_ip)"

  if command_exists hostnamectl; then
    system_run_root hostnamectl set-hostname "${HOST_FQDN}"
  else
    system_run_root hostname "${HOST_FQDN}"
  fi

  system_write_content_if_changed "/etc/hostname" "0644" "${HOST_FQDN}" || true

  local hosts_content
  hosts_content="$(cat <<EOF
127.0.0.1 localhost
${host_ip} ${HOST_FQDN} ${host_short}

# The following lines are desirable for IPv6 capable hosts
::1 ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
)"
  system_write_content_if_changed "/etc/hosts" "0644" "${hosts_content}" || true
}

system_configure_timezone() {
  if command_exists timedatectl; then
    system_run_root timedatectl set-timezone "${SYSTEM_TIMEZONE}"
    return 0
  fi

  local zoneinfo_path="/usr/share/zoneinfo/${SYSTEM_TIMEZONE}"
  [[ -f "${zoneinfo_path}" ]] || die "[system] timezone file not found: ${zoneinfo_path}"
  system_run_root ln -snf "${zoneinfo_path}" /etc/localtime
  system_write_content_if_changed "/etc/timezone" "0644" "${SYSTEM_TIMEZONE}" || true
}

system_render_unattended_50() {
  cat <<EOF
// Managed by infra-ubuntu-2404-openclaw (scripts/lib/system.sh)
Unattended-Upgrade::Allowed-Origins {
  "\${distro_id}:\${distro_codename}";
  "\${distro_id}:\${distro_codename}-security";
  "\${distro_id}ESMApps:\${distro_codename}-apps-security";
  "\${distro_id}ESM:\${distro_codename}-infra-security";
};

Unattended-Upgrade::Package-Blacklist {
};

Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
}

system_render_unattended_20() {
  cat <<'EOF'
// Managed by infra-ubuntu-2404-openclaw (scripts/lib/system.sh)
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
}

system_configure_unattended() {
  if [[ "${UNATTENDED_UPGRADES_ENABLE}" != "true" ]]; then
    log_info "[system] UNATTENDED_UPGRADES_ENABLE=false; skipping unattended-upgrades config"
    return 0
  fi

  local cfg_50
  local cfg_20
  cfg_50="$(system_render_unattended_50)"
  cfg_20="$(system_render_unattended_20)"

  system_write_content_if_changed "/etc/apt/apt.conf.d/50unattended-upgrades" "0644" "${cfg_50}" || true
  system_write_content_if_changed "/etc/apt/apt.conf.d/20auto-upgrades" "0644" "${cfg_20}" || true

  if command_exists systemctl; then
    system_run_root systemctl enable unattended-upgrades
  else
    log_warn "[system] systemctl not available; skipping unattended-upgrades service enablement"
  fi
}

system_render_fail2ban_jail() {
  cat <<EOF
# Managed by infra-ubuntu-2404-openclaw (scripts/lib/system.sh)
[sshd]
enabled = true
port = ${SSH_PORT}
backend = systemd
banaction = ufw
findtime = 10m
maxretry = 5
bantime = 1h
EOF
}

system_configure_fail2ban() {
  if [[ "${FAIL2BAN_ENABLE}" != "true" ]]; then
    log_info "[system] FAIL2BAN_ENABLE=false; skipping fail2ban config"
    return 0
  fi

  local jail_cfg
  jail_cfg="$(system_render_fail2ban_jail)"
  system_write_content_if_changed "/etc/fail2ban/jail.d/openclaw.local" "0644" "${jail_cfg}" || true

  if command_exists systemctl; then
    system_run_root systemctl enable --now fail2ban
    system_run_root systemctl restart fail2ban
  else
    log_warn "[system] systemctl not available; skipping fail2ban service management"
  fi
}

phase_system() {
  log_info "[system] applying hostname/timezone/unattended/fail2ban baseline"
  system_configure_timezone
  system_configure_hostname
  system_configure_unattended
  system_configure_fail2ban
  log_info "[system] system baseline complete"
}
