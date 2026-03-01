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

verify_edge_artifacts() {
  if [[ "${EDGE_ENABLE}" != "true" ]]; then
    return 0
  fi

  verify_require_file "${EDGE_ROOT_DIR}/edge/docker-compose.yml" "Edge compose file"
  verify_require_file "${EDGE_ROOT_DIR}/edge/traefik/traefik.yml" "Traefik config"
  verify_require_file "${EDGE_ROOT_DIR}/edge/cloudflared/config.yml" "Cloudflared config"

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
  verify_require_file "$(openclaw_compose_file_path)" "OpenClaw compose file"
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
}

verify_report_artifacts() {
  if [[ "${REPORT_ENABLE}" != "true" ]]; then
    return 0
  fi

  verify_require_file "${REPORT_SCRIPT}" "Report helper script"
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
    log_info "[verify] planned checks: security baseline, edge, dns, openclaw, apps, report, firewall runtime"
    return 0
  fi

  verify_issue_count=0
  verify_security_baseline
  verify_edge_artifacts
  verify_dns_artifacts
  verify_openclaw_artifacts
  verify_apps_artifacts
  verify_report_artifacts
  verify_firewall_runtime
  verify_finalize
}
