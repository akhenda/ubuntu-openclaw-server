#!/usr/bin/env bash

user_run_root() {
  if (( EUID == 0 )); then
    run_cmd "$@"
    return 0
  fi

  command_exists sudo || die "[user] sudo is required when not running as root"
  run_cmd sudo "$@"
}

user_passwd_file() {
  printf '%s' "${USER_PASSWD_FILE:-/etc/passwd}"
}

user_group_file() {
  printf '%s' "${USER_GROUP_FILE:-/etc/group}"
}

user_exists() {
  local username="$1"
  local passwd_file
  passwd_file="$(user_passwd_file)"
  [[ -f "${passwd_file}" ]] || die "[user] passwd file not found: ${passwd_file}"
  awk -F: -v name="${username}" '$1 == name { found=1 } END { exit(found ? 0 : 1) }' "${passwd_file}"
}

user_home() {
  local username="$1"
  local passwd_file
  passwd_file="$(user_passwd_file)"
  awk -F: -v name="${username}" '$1 == name { print $6; exit }' "${passwd_file}"
}

group_exists() {
  local group_name="$1"
  local group_file
  group_file="$(user_group_file)"
  [[ -f "${group_file}" ]] || die "[user] group file not found: ${group_file}"
  awk -F: -v name="${group_name}" '$1 == name { found=1 } END { exit(found ? 0 : 1) }' "${group_file}"
}

group_has_member() {
  local group_name="$1"
  local username="$2"
  local group_file
  group_file="$(user_group_file)"
  awk -F: -v g="${group_name}" -v u="${username}" '
    $1 == g {
      n = split($4, members, ",")
      for (i = 1; i <= n; i++) {
        if (members[i] == u) {
          found = 1
          exit
        }
      }
    }
    END { exit(found ? 0 : 1) }
  ' "${group_file}"
}

ensure_sudo_group() {
  if group_exists "sudo"; then
    log_info "[user] sudo group already exists"
    return 0
  fi

  log_info "[user] creating sudo group"
  user_run_root groupadd sudo
}

ensure_admin_user() {
  if user_exists "${ADMIN_USER}"; then
    log_info "[user] admin user '${ADMIN_USER}' already exists"
    user_run_root usermod -s "${ADMIN_USER_SHELL}" "${ADMIN_USER}"
  else
    log_info "[user] creating admin user '${ADMIN_USER}'"
    user_run_root useradd --create-home --shell "${ADMIN_USER_SHELL}" --groups sudo "${ADMIN_USER}"
  fi

  if group_has_member "sudo" "${ADMIN_USER}"; then
    log_info "[user] admin user '${ADMIN_USER}' already in sudo group"
  else
    log_info "[user] adding admin user '${ADMIN_USER}' to sudo group"
    user_run_root usermod -aG sudo "${ADMIN_USER}"
  fi
}

ensure_runtime_user() {
  if user_exists "${RUNTIME_USER}"; then
    log_info "[user] runtime user '${RUNTIME_USER}' already exists"
    user_run_root usermod -s "${RUNTIME_USER_SHELL}" "${RUNTIME_USER}"
  else
    log_info "[user] creating runtime user '${RUNTIME_USER}'"
    user_run_root useradd --create-home --shell "${RUNTIME_USER_SHELL}" --user-group "${RUNTIME_USER}"
  fi

  if group_has_member "sudo" "${RUNTIME_USER}"; then
    log_warn "[user] runtime user '${RUNTIME_USER}' is in sudo group; removing"
    user_run_root gpasswd -d "${RUNTIME_USER}" sudo
  fi

  log_info "[user] locking runtime user password"
  user_run_root usermod -L "${RUNTIME_USER}"
}

ensure_admin_authorized_key() {
  local admin_home
  admin_home="$(user_home "${ADMIN_USER}")"
  if [[ -z "${admin_home}" ]]; then
    admin_home="/home/${ADMIN_USER}"
  fi

  local ssh_dir="${admin_home}/.ssh"
  local auth_file="${ssh_dir}/authorized_keys"

  log_info "[user] ensuring authorized key for '${ADMIN_USER}'"
  user_run_root install -d -m 0700 -o "${ADMIN_USER}" -g "${ADMIN_USER}" "${ssh_dir}"
  user_run_root touch "${auth_file}"
  user_run_root chown "${ADMIN_USER}:${ADMIN_USER}" "${auth_file}"
  user_run_root chmod 0600 "${auth_file}"

  local key_q file_q
  key_q="$(printf '%q' "${ADMIN_SSH_PUBLIC_KEY}")"
  file_q="$(printf '%q' "${auth_file}")"
  user_run_root /bin/bash -c "grep -Fqx -- ${key_q} ${file_q} || printf '%s\n' ${key_q} >> ${file_q}"
}

ensure_sudoers_policy() {
  local sudoers_file="${SUDOERS_FILE:-/etc/sudoers}"
  if [[ ! -f "${sudoers_file}" ]]; then
    log_warn "[user] sudoers file not found at ${sudoers_file}; skipping sudoers policy check"
    return 0
  fi

  if grep -Eq '^%sudo[[:space:]]+ALL=\(ALL:ALL\)[[:space:]]+ALL' "${sudoers_file}"; then
    log_info "[user] sudoers policy for sudo group already present"
    return 0
  fi

  log_warn "[user] sudoers policy for sudo group missing in ${sudoers_file}; adding drop-in"
  user_run_root /bin/bash -c "printf '%s\n' '%sudo ALL=(ALL:ALL) ALL' > /etc/sudoers.d/99-sudo-group"
  user_run_root chmod 0440 /etc/sudoers.d/99-sudo-group
}

disable_or_remove_default_ubuntu_user() {
  if [[ "${REMOVE_DEFAULT_UBUNTU_USER}" != "true" ]]; then
    log_info "[user] REMOVE_DEFAULT_UBUNTU_USER=false; keeping ubuntu user untouched"
    return 0
  fi

  if ! user_exists "ubuntu"; then
    log_info "[user] default ubuntu user not present"
    return 0
  fi

  local current_user="${CURRENT_LOGIN_USER:-${SUDO_USER:-${USER:-}}}"
  if [[ "${current_user}" == "ubuntu" ]]; then
    die "[user] refusing to remove 'ubuntu' while current login user is ubuntu"
  fi

  log_info "[user] removing default ubuntu user"
  user_run_root userdel -r ubuntu
}

phase_user() {
  log_info "[user] configuring dual-user model"
  ensure_sudo_group
  ensure_admin_user
  ensure_runtime_user
  ensure_admin_authorized_key
  ensure_sudoers_policy
  disable_or_remove_default_ubuntu_user
  log_info "[user] dual-user setup complete"
}
