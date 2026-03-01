#!/usr/bin/env bash

oh_my_zsh_run_root() {
  if (( EUID == 0 )); then
    run_cmd "$@"
    return $?
  fi

  command_exists sudo || die "[oh-my-zsh] sudo is required when not running as root"
  run_cmd sudo "$@"
}

oh_my_zsh_home() {
  local user_name="$1"
  if command_exists getent; then
    getent passwd "${user_name}" | awk -F: '{print $6}'
    return 0
  fi

  local passwd_file="${USER_PASSWD_FILE:-/etc/passwd}"
  awk -F: -v name="${user_name}" '$1 == name { print $6; exit }' "${passwd_file}"
}

oh_my_zsh_write_content_if_changed() {
  local target="$1"
  local owner_user="$2"
  local mode="$3"
  local content="$4"

  local tmp_file
  tmp_file="$(mktemp)"
  printf '%s\n' "${content}" > "${tmp_file}"

  local changed="true"
  if [[ -f "${target}" ]] && cmp -s "${target}" "${tmp_file}"; then
    changed="false"
  fi

  if [[ "${changed}" == "false" ]]; then
    log_info "[oh-my-zsh] no changes for ${target}"
    rm -f "${tmp_file}"
    return 1
  fi

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[oh-my-zsh] [dry-run] would update ${target}"
    rm -f "${tmp_file}"
    return 0
  fi

  oh_my_zsh_run_root install -d -m 0755 "$(dirname "${target}")"
  oh_my_zsh_run_root cp "${tmp_file}" "${target}"
  oh_my_zsh_run_root chown "${owner_user}:${owner_user}" "${target}"
  oh_my_zsh_run_root chmod "${mode}" "${target}"
  rm -f "${tmp_file}"
  return 0
}

oh_my_zsh_render_zshrc() {
  local user_name="$1"
  cat <<EOF
# Path to your oh-my-zsh installation.
export ZSH=/home/${user_name}/.oh-my-zsh

# Set name of theme to load
ZSH_THEME="${OH_MY_ZSH_THEME}"

# Enable oh my zsh plugins
plugins=(${OH_MY_ZSH_PLUGINS})

# Load oh my zsh
source \$ZSH/oh-my-zsh.sh

# Load z
source ~/z.sh

# Configure PATH
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games"

# Lines configured by zsh-newuser-install
HISTFILE=~/.histfile
HISTSIZE=1000
SAVEHIST=1000
setopt appendhistory autocd extendedglob
bindkey -e
EOF
}

phase_oh_my_zsh() {
  if [[ "${OH_MY_ZSH_ENABLE}" != "true" ]]; then
    log_info "[oh-my-zsh] OH_MY_ZSH_ENABLE=false; skipping shell customization"
    return 0
  fi

  log_info "[oh-my-zsh] configuring oh-my-zsh for ${ADMIN_USER}"

  local user_home=""
  user_home="$(oh_my_zsh_home "${ADMIN_USER}")"
  [[ -n "${user_home}" ]] || die "[oh-my-zsh] could not resolve home directory for ${ADMIN_USER}"

  oh_my_zsh_run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends zsh

  local ohmyzsh_dir="${user_home}/.oh-my-zsh"
  if [[ -d "${ohmyzsh_dir}/.git" ]]; then
    oh_my_zsh_run_root git -C "${ohmyzsh_dir}" pull --ff-only
  else
    oh_my_zsh_run_root rm -rf "${ohmyzsh_dir}"
    oh_my_zsh_run_root git clone --depth 1 "${OH_MY_ZSH_REPO}" "${ohmyzsh_dir}"
  fi

  local theme_path="${ohmyzsh_dir}/themes/guru2.zsh-theme"
  local zshrc_path="${user_home}/.zshrc"
  local z_sh_path="${user_home}/z.sh"

  oh_my_zsh_run_root curl -fsSL "${OH_MY_ZSH_THEME_URL}" -o "${theme_path}"
  oh_my_zsh_run_root curl -fsSL "${OH_MY_Z_SH_URL}" -o "${z_sh_path}"
  oh_my_zsh_run_root chown -R "${ADMIN_USER}:${ADMIN_USER}" "${ohmyzsh_dir}"
  oh_my_zsh_run_root chown "${ADMIN_USER}:${ADMIN_USER}" "${z_sh_path}"
  oh_my_zsh_run_root chmod 0644 "${theme_path}" "${z_sh_path}"

  local zshrc_content=""
  zshrc_content="$(oh_my_zsh_render_zshrc "${ADMIN_USER}")"
  oh_my_zsh_write_content_if_changed "${zshrc_path}" "${ADMIN_USER}" "0644" "${zshrc_content}" || true

  oh_my_zsh_run_root usermod -s /bin/zsh "${ADMIN_USER}"

  log_info "[oh-my-zsh] shell customization complete"
}
