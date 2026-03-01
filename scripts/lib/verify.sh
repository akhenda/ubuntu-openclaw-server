#!/usr/bin/env bash

verify_issue_count=0

verify_run_root() {
  if (( EUID == 0 )); then
    "$@"
    return $?
  fi

  command_exists sudo || return 1
  sudo "$@"
}

verify_record_issue() {
  local message="$1"
  verify_issue_count=$((verify_issue_count + 1))
  log_error "[verify] ${message}"
}

verify_require_file() {
  local path="$1"
  local label="$2"
  if [[ ! -f "${path}" ]]; then
    verify_record_issue "${label} missing: ${path}"
  fi
}

verify_require_contains() {
  local path="$1"
  local pattern="$2"
  local label="$3"

  if [[ ! -f "${path}" ]]; then
    verify_record_issue "${label} missing: ${path}"
    return 0
  fi

  if ! grep -Fq -- "${pattern}" "${path}"; then
    verify_record_issue "${label} missing expected value '${pattern}' in ${path}"
  fi
}

verify_require_not_contains() {
  local path="$1"
  local pattern="$2"
  local label="$3"

  if [[ ! -f "${path}" ]]; then
    verify_record_issue "${label} missing: ${path}"
    return 0
  fi

  if grep -Fq -- "${pattern}" "${path}"; then
    verify_record_issue "${label} contains forbidden value '${pattern}' in ${path}"
  fi
}

verify_finalize() {
  if (( verify_issue_count == 0 )); then
    log_info "[verify] verification checks passed"
    return 0
  fi

  if [[ "${VERIFY_STRICT}" == "true" ]]; then
    die "[verify] verification failed with ${verify_issue_count} issue(s)"
  fi

  log_warn "[verify] verification reported ${verify_issue_count} issue(s), continuing because VERIFY_STRICT=false"
}

verify_security_baseline() {
  local ssh_dropin="${SSHD_HARDENING_FILE:-/etc/ssh/sshd_config.d/99-openclaw-hardening.conf}"
  verify_require_file "${ssh_dropin}" "SSH hardening drop-in"
  verify_require_contains "${ssh_dropin}" "Port ${SSH_PORT}" "SSH hardening drop-in"
  verify_require_contains "${ssh_dropin}" "PermitRootLogin no" "SSH hardening drop-in"
  verify_require_contains "${ssh_dropin}" "PasswordAuthentication no" "SSH hardening drop-in"
}

verify_system_baseline() {
  verify_require_file "/etc/hostname" "Hostname file"
  verify_require_contains "/etc/hostname" "${HOST_FQDN}" "Hostname file"

  if [[ "${UNATTENDED_UPGRADES_ENABLE}" == "true" ]]; then
    verify_require_file "/etc/apt/apt.conf.d/50unattended-upgrades" "Unattended upgrades config"
    verify_require_file "/etc/apt/apt.conf.d/20auto-upgrades" "APT periodic config"
    verify_require_contains "/etc/apt/apt.conf.d/50unattended-upgrades" '${distro_id}:${distro_codename}-security' "Unattended upgrades config"
  fi

  if [[ "${FAIL2BAN_ENABLE}" == "true" ]]; then
    verify_require_file "/etc/fail2ban/jail.d/openclaw.local" "Fail2ban jail override"
    verify_require_contains "/etc/fail2ban/jail.d/openclaw.local" "port = ${SSH_PORT}" "Fail2ban jail override"
  fi

  if command_exists timedatectl; then
    local tz=""
    tz="$(timedatectl show --property=Timezone --value 2>/dev/null || true)"
    if [[ -n "${tz}" && "${tz}" != "${SYSTEM_TIMEZONE}" ]]; then
      verify_record_issue "system timezone mismatch (expected ${SYSTEM_TIMEZONE}, got ${tz})"
    fi
  fi

  if command_exists systemctl; then
    if [[ "${UNATTENDED_UPGRADES_ENABLE}" == "true" ]]; then
      if ! verify_run_root systemctl is-enabled unattended-upgrades >/dev/null 2>&1; then
        verify_record_issue "unattended-upgrades service is not enabled"
      fi
    fi
    if [[ "${FAIL2BAN_ENABLE}" == "true" ]]; then
      if ! verify_run_root systemctl is-enabled fail2ban >/dev/null 2>&1; then
        verify_record_issue "fail2ban service is not enabled"
      fi
      if ! verify_run_root systemctl is-active fail2ban >/dev/null 2>&1; then
        verify_record_issue "fail2ban service is not active"
      fi
    fi
  fi
}

verify_edge_artifacts() {
  if [[ "${EDGE_ENABLE}" != "true" ]]; then
    return 0
  fi

  verify_require_file "${EDGE_ROOT_DIR}/edge/docker-compose.yml" "Edge compose file"
  verify_require_file "${EDGE_ROOT_DIR}/edge/traefik/traefik.yml" "Traefik config"
  verify_require_file "${EDGE_ROOT_DIR}/edge/traefik/dynamic/openclaw.yml" "Traefik OpenClaw dynamic config"
  verify_require_file "${EDGE_ROOT_DIR}/edge/cloudflared/config.yml" "Cloudflared config"

  if [[ "${SOCKET_PROXY_ENABLE}" == "true" ]]; then
    local edge_compose="${EDGE_ROOT_DIR}/edge/docker-compose.yml"
    local traefik_cfg="${EDGE_ROOT_DIR}/edge/traefik/traefik.yml"
    verify_require_contains "${edge_compose}" "docker-socket-proxy:" "Edge compose file"
    verify_require_contains "${traefik_cfg}" 'endpoint: "tcp://' "Traefik config"
    if [[ -f "${edge_compose}" ]]; then
      local sock_mount_count
      sock_mount_count="$(grep -Fc '/var/run/docker.sock:/var/run/docker.sock:ro' "${edge_compose}")"
      if [[ "${sock_mount_count}" != "1" ]]; then
        verify_record_issue "Edge compose should mount docker.sock exactly once (socket proxy only), found: ${sock_mount_count}"
      fi
    fi
  fi

  if command_exists docker; then
    if ! verify_run_root docker network inspect "${EDGE_NETWORK_NAME}" >/dev/null 2>&1; then
      verify_record_issue "Docker network '${EDGE_NETWORK_NAME}' not found"
    fi
  else
    verify_record_issue "docker command not found for edge verification"
  fi
}

verify_dns_artifacts() {
  if [[ "${DNS_ENABLE}" != "true" ]]; then
    return 0
  fi

  verify_require_file "${DNS_BIN_DIR}/cf_dns_ensure_wildcard.sh" "DNS ensure helper"
  verify_require_file "${DNS_BIN_DIR}/cf_dns_upsert_subdomain.sh" "DNS upsert helper"
}

verify_openclaw_artifacts() {
  if [[ "${OPENCLAW_ENABLE}" != "true" ]]; then
    return 0
  fi

  verify_require_file "${OPENCLAW_CONFIG_FILE}" "OpenClaw config"
  verify_require_file "$(openclaw_env_file_path)" "OpenClaw env file"
  verify_require_file "$(openclaw_cli_wrapper_path)" "OpenClaw CLI wrapper"
  verify_require_file "${OPENCLAW_POLICY_FILE}" "OpenClaw deploy policy file"

  verify_require_contains "${OPENCLAW_CONFIG_FILE}" '"bootstrap-extra-files"' "OpenClaw config"
  verify_require_contains "${OPENCLAW_POLICY_FILE}" 'Never publish ports' "OpenClaw deploy policy file"
}

verify_apps_artifacts() {
  if [[ "${APPS_ENABLE}" != "true" ]]; then
    return 0
  fi

  verify_require_file "${APPS_COMPOSE_FILE}" "Apps compose file"
  verify_require_file "${APPS_REGISTER_SCRIPT}" "App register helper"
  verify_require_file "${APPS_DEPLOY_SCRIPT}" "App deploy helper"
  verify_require_file "${DNS_BIN_DIR}/ensure_hub.sh" "Hub ensure helper"
  if [[ "${HUB_ENABLE}" == "true" ]]; then
    verify_require_contains "${APPS_REGISTER_SCRIPT}" "homepage.href=https://" "App register helper"
    verify_require_contains "${DNS_BIN_DIR}/ensure_hub.sh" "ghcr.io/gethomepage/homepage:latest" "Hub ensure helper"
  fi
}

verify_report_artifacts() {
  if [[ "${REPORT_ENABLE}" != "true" ]]; then
    return 0
  fi

  verify_require_file "${REPORT_SCRIPT}" "Report helper script"
}

verify_systemd_artifacts() {
  if [[ "${EDGE_ENABLE}" == "true" && "${EDGE_MANAGE_SYSTEMD}" == "true" ]]; then
    verify_require_file "${EDGE_SYSTEMD_UNIT}" "Edge systemd unit"
  fi

  if [[ "${OPENCLAW_ENABLE}" == "true" && "${OPENCLAW_MANAGE_SYSTEMD}" == "true" ]]; then
    verify_require_file "${OPENCLAW_SYSTEMD_UNIT}" "OpenClaw systemd unit"
  fi

  if [[ "${APPS_ENABLE}" == "true" && "${APPS_MANAGE_SYSTEMD}" == "true" ]]; then
    verify_require_file "${APPS_SYSTEMD_UNIT}" "Apps systemd unit"
  fi
}

verify_motd_artifacts() {
  if [[ "${MOTD_ENABLE}" != "true" ]]; then
    return 0
  fi

  verify_require_file "${MOTD_SCRIPT_PATH}" "MOTD status script"
}

verify_oh_my_zsh_artifacts() {
  if [[ "${OH_MY_ZSH_ENABLE}" != "true" ]]; then
    return 0
  fi

  local zshrc_path="/home/${ADMIN_USER}/.zshrc"
  verify_require_file "${zshrc_path}" "Admin .zshrc"
  verify_require_contains "${zshrc_path}" "ZSH_THEME=\"${OH_MY_ZSH_THEME}\"" "Admin .zshrc"
  verify_require_contains "${zshrc_path}" "plugins=(${OH_MY_ZSH_PLUGINS})" "Admin .zshrc"
}

verify_tailscale_runtime() {
  if [[ "${TAILSCALE_ENABLE}" != "true" ]]; then
    return 0
  fi

  if ! command_exists tailscale; then
    verify_record_issue "tailscale command not found"
    return 0
  fi

  if ! command_exists systemctl; then
    log_warn "[verify] systemctl not available; skipping tailscaled service checks"
    return 0
  fi

  if ! verify_run_root systemctl is-enabled tailscaled >/dev/null 2>&1; then
    verify_record_issue "tailscaled service is not enabled"
  fi

  if ! verify_run_root systemctl is-active tailscaled >/dev/null 2>&1; then
    verify_record_issue "tailscaled service is not active"
  fi
}

verify_firewall_runtime() {
  if [[ "${FIREWALL_ENABLE}" != "true" ]]; then
    return 0
  fi

  if ! command_exists ufw; then
    verify_record_issue "ufw command not found for firewall verification"
    return 0
  fi

  local ufw_status
  if ! ufw_status="$(verify_run_root ufw status 2>/dev/null)"; then
    verify_record_issue "unable to run 'ufw status'"
    return 0
  fi

  if ! grep -Fq "Status: active" <<< "${ufw_status}"; then
    verify_record_issue "ufw is not active"
  fi
}

phase_verify() {
  if [[ "${VERIFY_ENABLE}" != "true" ]]; then
    log_info "[verify] VERIFY_ENABLE=false; skipping verification checks"
    return 0
  fi

  log_info "[verify] running post-install verification checks"

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[verify] dry-run mode: skipping live state assertions"
    log_info "[verify] planned checks: security baseline, system baseline, edge, dns, openclaw, apps, report, systemd, motd, oh-my-zsh, tailscale runtime, firewall runtime"
    return 0
  fi

  verify_issue_count=0
  verify_security_baseline
  verify_system_baseline
  verify_edge_artifacts
  verify_dns_artifacts
  verify_openclaw_artifacts
  verify_apps_artifacts
  verify_report_artifacts
  verify_systemd_artifacts
  verify_motd_artifacts
  verify_oh_my_zsh_artifacts
  verify_tailscale_runtime
  verify_firewall_runtime
  verify_finalize
}
