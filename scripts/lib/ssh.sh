#!/usr/bin/env bash

ssh_run_root() {
  if (( EUID == 0 )); then
    run_cmd "$@"
    return 0
  fi

  command_exists sudo || die "[ssh] sudo is required when not running as root"
  run_cmd sudo "$@"
}

sshd_main_config_path() {
  printf '%s' "${SSHD_MAIN_CONFIG:-/etc/ssh/sshd_config}"
}

sshd_config_dir_path() {
  printf '%s' "${SSHD_CONFIG_DIR:-/etc/ssh/sshd_config.d}"
}

sshd_dropin_path() {
  if [[ -n "${SSHD_HARDENING_FILE:-}" ]]; then
    printf '%s' "${SSHD_HARDENING_FILE}"
    return 0
  fi

  printf '%s/99-openclaw-hardening.conf' "$(sshd_config_dir_path)"
}

sshd_binary_path() {
  if [[ -n "${SSHD_BIN:-}" ]]; then
    printf '%s' "${SSHD_BIN}"
    return 0
  fi

  if command_exists /usr/sbin/sshd; then
    printf '%s' "/usr/sbin/sshd"
    return 0
  fi

  if command_exists sshd; then
    command -v sshd
    return 0
  fi

  printf '%s' "/usr/sbin/sshd"
}

ssh_service_name() {
  printf '%s' "${SSH_SERVICE_NAME:-ssh}"
}

ssh_write_content_if_changed() {
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
    log_info "[ssh] no changes for ${target}"
    rm -f "${tmp_file}"
    return 1
  fi

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[ssh] [dry-run] would update ${target}"
    rm -f "${tmp_file}"
    return 0
  fi

  ssh_run_root install -d -m 0755 "$(dirname "${target}")"
  ssh_run_root cp "${tmp_file}" "${target}"
  ssh_run_root chown root:root "${target}"
  ssh_run_root chmod "${mode}" "${target}"
  rm -f "${tmp_file}"
  return 0
}

ssh_ensure_include_directive() {
  local main_config
  main_config="$(sshd_main_config_path)"

  require_file "${main_config}"

  local include_regex='^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf([[:space:]]|$)'
  if grep -Eq "${include_regex}" "${main_config}"; then
    log_info "[ssh] sshd include directive already present"
    return 1
  fi

  log_warn "[ssh] sshd include directive missing; prepending default include"

  local existing
  existing="$(cat "${main_config}")"
  local updated
  updated=$'Include /etc/ssh/sshd_config.d/*.conf\n'"${existing}"

  ssh_write_content_if_changed "${main_config}" "0644" "${updated}" || true
  return 0
}

ssh_render_hardening_dropin() {
  cat <<EOF
# Managed by infra-ubuntu-2404-openclaw (scripts/lib/ssh.sh)
Port ${SSH_PORT}
Protocol 2
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
UsePAM yes
PermitEmptyPasswords no
MaxAuthTries 2
UseDNS no
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
PrintMotd no
PrintLastLog no
AllowUsers ${ADMIN_USER}
EOF
}

ssh_ensure_hardening_dropin() {
  local dropin
  dropin="$(sshd_dropin_path)"
  local content
  content="$(ssh_render_hardening_dropin)"

  ssh_write_content_if_changed "${dropin}" "0644" "${content}" || return 1
  return 0
}

ssh_validate_config() {
  local sshd_bin
  sshd_bin="$(sshd_binary_path)"
  local main_config
  main_config="$(sshd_main_config_path)"

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[ssh] [dry-run] would validate ssh config using: ${sshd_bin} -t -f ${main_config}"
    return 0
  fi

  if [[ ! -x "${sshd_bin}" ]] && ! command_exists "${sshd_bin}"; then
    die "[ssh] sshd binary not found or not executable: ${sshd_bin}"
  fi

  ssh_run_root "${sshd_bin}" -t -f "${main_config}"
}

ssh_reload_service() {
  local service_name
  service_name="$(ssh_service_name)"

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[ssh] [dry-run] would restart ssh service '${service_name}'"
    return 0
  fi

  if command_exists systemctl; then
    ssh_run_root systemctl restart "${service_name}"
    return 0
  fi

  if command_exists service; then
    ssh_run_root service "${service_name}" restart
    return 0
  fi

  log_warn "[ssh] could not restart ssh service automatically (no systemctl/service command found)"
}

ssh_backup_file_if_exists() {
  local file="$1"
  local backup_var_name="$2"

  if [[ ! -f "${file}" ]]; then
    printf -v "${backup_var_name}" '%s' ""
    return 0
  fi

  local backup
  backup="$(mktemp)"
  cp "${file}" "${backup}"
  printf -v "${backup_var_name}" '%s' "${backup}"
}

ssh_restore_backup_if_present() {
  local backup="$1"
  local target="$2"
  if [[ -n "${backup}" && -f "${backup}" ]]; then
    ssh_run_root cp "${backup}" "${target}"
  fi
}

ssh_cleanup_backup_if_present() {
  local backup="$1"
  if [[ -n "${backup}" && -f "${backup}" ]]; then
    rm -f "${backup}"
  fi
}

phase_ssh() {
  log_info "[ssh] configuring ssh hardening"

  local main_config
  local dropin
  main_config="$(sshd_main_config_path)"
  dropin="$(sshd_dropin_path)"

  local main_backup=""
  local dropin_backup=""
  if [[ "${DRY_RUN:-false}" != "true" ]]; then
    ssh_backup_file_if_exists "${main_config}" main_backup
    ssh_backup_file_if_exists "${dropin}" dropin_backup
  fi

  local changed="false"
  if ssh_ensure_include_directive; then
    changed="true"
  fi

  if ssh_ensure_hardening_dropin; then
    changed="true"
  fi

  if [[ "${changed}" == "false" ]]; then
    ssh_cleanup_backup_if_present "${main_backup}"
    ssh_cleanup_backup_if_present "${dropin_backup}"
    log_info "[ssh] no sshd config changes detected"
    return 0
  fi

  if ! ssh_validate_config; then
    log_error "[ssh] sshd validation failed; restoring previous configuration"
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
      ssh_restore_backup_if_present "${main_backup}" "${main_config}"
      ssh_restore_backup_if_present "${dropin_backup}" "${dropin}"
    fi
    ssh_cleanup_backup_if_present "${main_backup}"
    ssh_cleanup_backup_if_present "${dropin_backup}"
    die "[ssh] failed to apply ssh hardening safely"
  fi

  ssh_reload_service
  ssh_cleanup_backup_if_present "${main_backup}"
  ssh_cleanup_backup_if_present "${dropin_backup}"

  log_info "[ssh] ssh hardening applied"
}
