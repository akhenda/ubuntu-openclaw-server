#!/usr/bin/env bash

firewall_run_root() {
  if (( EUID == 0 )); then
    run_cmd "$@"
    return $?
  fi

  command_exists sudo || die "[firewall] sudo is required when not running as root"
  run_cmd sudo "$@"
}

ufw_cmd_path() {
  if [[ -n "${UFW_BIN:-}" ]]; then
    printf '%s' "${UFW_BIN}"
    return 0
  fi

  if command_exists ufw; then
    command -v ufw
    return 0
  fi

  printf '%s' "ufw"
}

ufw_is_available() {
  local ufw_cmd="$1"

  if [[ "$ufw_cmd" == */* ]]; then
    [[ -x "$ufw_cmd" ]]
    return $?
  fi

  command_exists "$ufw_cmd"
}

firewall_require_ufw() {
  local ufw_cmd="$1"
  if ufw_is_available "${ufw_cmd}"; then
    return 0
  fi

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_warn "[firewall] ufw binary not found; continuing due to --dry-run"
    return 0
  fi

  die "[firewall] ufw binary not found. Ensure packages phase installed ufw."
}

firewall_allow_port_tcp() {
  local ufw_cmd="$1"
  local port="$2"
  firewall_run_root "${ufw_cmd}" allow "${port}/tcp"
}

firewall_apply_extra_ports() {
  local ufw_cmd="$1"
  local raw="${FIREWALL_EXTRA_TCP_PORTS:-}"
  [[ -z "${raw}" ]] && return 0

  local normalized="${raw//,/ }"
  local seen=",${SSH_PORT},"
  local port=""

  for port in ${normalized}; do
    validate_tcp_port "${port}" || die "[firewall] invalid TCP port in FIREWALL_EXTRA_TCP_PORTS: ${port}"

    if [[ "${seen}" == *",${port},"* ]]; then
      log_info "[firewall] skipping duplicate/implicit port ${port}"
      continue
    fi

    if [[ "${port}" == "22" && "${SSH_PORT}" != "22" ]]; then
      log_warn "[firewall] skipping extra allow for port 22 because SSH is hardened on ${SSH_PORT}"
      seen+="${port},"
      continue
    fi

    log_info "[firewall] allowing extra TCP port ${port}"
    firewall_allow_port_tcp "${ufw_cmd}" "${port}"
    seen+="${port},"
  done
}

phase_firewall() {
  if [[ "${FIREWALL_ENABLE}" != "true" ]]; then
    log_info "[firewall] FIREWALL_ENABLE=false; skipping ufw configuration"
    return 0
  fi

  log_info "[firewall] configuring ufw baseline"

  local ufw_cmd
  ufw_cmd="$(ufw_cmd_path)"
  firewall_require_ufw "${ufw_cmd}"

  firewall_run_root "${ufw_cmd}" default deny incoming
  firewall_run_root "${ufw_cmd}" default allow outgoing

  firewall_allow_port_tcp "${ufw_cmd}" "${SSH_PORT}"
  if [[ "${SSH_PORT}" != "22" ]]; then
    firewall_run_root "${ufw_cmd}" deny 22/tcp
  fi

  if [[ "${FIREWALL_ALLOW_HTTP}" == "true" ]]; then
    firewall_allow_port_tcp "${ufw_cmd}" "80"
  fi

  if [[ "${FIREWALL_ALLOW_HTTPS}" == "true" ]]; then
    firewall_allow_port_tcp "${ufw_cmd}" "443"
  fi

  if [[ "${EDGE_ENABLE}" == "true" && "${OPENCLAW_ENABLE}" == "true" ]]; then
    log_info "[firewall] allowing edge subnet ${EDGE_SUBNET} to OpenClaw gateway port ${OPENCLAW_GATEWAY_PORT}"
    firewall_run_root "${ufw_cmd}" allow from "${EDGE_SUBNET}" to any port "${OPENCLAW_GATEWAY_PORT}" proto tcp
  fi

  firewall_apply_extra_ports "${ufw_cmd}"

  firewall_run_root "${ufw_cmd}" --force enable

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[firewall] [dry-run] would show ufw status verbose"
  else
    firewall_run_root "${ufw_cmd}" status verbose
  fi

  log_info "[firewall] ufw baseline applied"
}
