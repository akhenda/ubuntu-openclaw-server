#!/usr/bin/env bash

tailscale_run_root() {
  if (( EUID == 0 )); then
    run_cmd "$@"
    return $?
  fi

  command_exists sudo || die "[tailscale] sudo is required when not running as root"
  run_cmd sudo "$@"
}

tailscale_cmd_path() {
  if [[ -n "${TAILSCALE_BIN:-}" ]]; then
    printf '%s' "${TAILSCALE_BIN}"
    return 0
  fi

  if command_exists tailscale; then
    command -v tailscale
    return 0
  fi

  printf '%s' "tailscale"
}

tailscale_is_placeholder_authkey() {
  [[ "${TAILSCALE_AUTHKEY}" == tskey-auth-test-placeholder-* ]]
}

tailscale_install_repo() {
  local codename="${VERSION_CODENAME:-noble}"
  local keyring="/usr/share/keyrings/tailscale-archive-keyring.gpg"
  local list_file="/etc/apt/sources.list.d/tailscale.list"

  tailscale_run_root install -m 0755 -d /usr/share/keyrings
  tailscale_run_root curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${codename}.noarmor.gpg" -o "${keyring}"
  tailscale_run_root curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${codename}.tailscale-keyring.list" -o "${list_file}"
}

tailscale_install_package() {
  tailscale_apt_with_retry apt-get update
  tailscale_apt_with_retry apt-get install -y --no-install-recommends tailscale
}

tailscale_enable_service() {
  if command_exists systemctl; then
    tailscale_run_root systemctl enable --now tailscaled
    return 0
  fi

  log_warn "[tailscale] systemctl not available; skipping tailscaled enablement"
}

tailscale_matches_desired_state() {
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    return 1
  fi

  local tailscale_cmd
  tailscale_cmd="$(tailscale_cmd_path)"
  command_exists "${tailscale_cmd}" || return 1
  command_exists jq || return 1

  local status_json=""
  if ! status_json="$(tailscale_run_root "${tailscale_cmd}" status --json 2>/dev/null)"; then
    return 1
  fi

  [[ -n "${status_json}" ]] || return 1

  local backend_state=""
  local self_host=""
  backend_state="$(jq -r '.BackendState // empty' <<< "${status_json}" 2>/dev/null || true)"
  self_host="$(jq -r '.Self.HostName // empty' <<< "${status_json}" 2>/dev/null || true)"

  [[ "${backend_state}" == "Running" ]] || return 1
  [[ "${self_host}" == "${TAILSCALE_HOSTNAME}" ]] || return 1

  local prefs_json=""
  if ! prefs_json="$(tailscale_run_root "${tailscale_cmd}" debug prefs --json 2>/dev/null)"; then
    return 1
  fi

  local run_ssh=""
  run_ssh="$(jq -r '.RunSSH // empty' <<< "${prefs_json}" 2>/dev/null || true)"

  local desired_ssh="false"
  if [[ "${TAILSCALE_SSH}" == "true" ]]; then
    desired_ssh="true"
  fi

  [[ "${run_ssh}" == "${desired_ssh}" ]]
}

tailscale_up_args() {
  local -n ref="$1"
  local tailscale_cmd
  tailscale_cmd="$(tailscale_cmd_path)"
  ref=("${tailscale_cmd}" up --authkey "${TAILSCALE_AUTHKEY}" --hostname "${TAILSCALE_HOSTNAME}")

  if [[ "${TAILSCALE_SSH}" == "true" ]]; then
    ref+=(--ssh)
  else
    ref+=(--ssh=false)
  fi

  if [[ -n "${TAILSCALE_EXTRA_ARGS:-}" ]]; then
    local -a extra_args=()
    # shellcheck disable=SC2206
    extra_args=(${TAILSCALE_EXTRA_ARGS})
    ref+=("${extra_args[@]}")
  fi
}

tailscale_apt_with_retry() {
  local max_attempts="${APT_RETRY_ATTEMPTS:-20}"
  local sleep_seconds="${APT_RETRY_DELAY_SECONDS:-5}"
  local attempt=1

  while true; do
    if tailscale_run_root env DEBIAN_FRONTEND=noninteractive "$@"; then
      return 0
    fi

    if (( attempt >= max_attempts )); then
      return 1
    fi

    log_warn "[tailscale] apt command failed (attempt ${attempt}/${max_attempts}); retrying in ${sleep_seconds}s"
    attempt=$((attempt + 1))
    sleep "${sleep_seconds}"
  done
}

tailscale_connect() {
  if tailscale_matches_desired_state; then
    log_info "[tailscale] desired state already active; skipping tailscale up"
    return 0
  fi

  if tailscale_is_placeholder_authkey && [[ "${TAILSCALE_ALLOW_PLACEHOLDER_AUTHKEY}" == "true" ]]; then
    log_warn "[tailscale] placeholder authkey allowed for test mode; skipping tailscale up"
    return 0
  fi

  local -a args=()
  tailscale_up_args args
  tailscale_run_root "${args[@]}"
}

phase_tailscale() {
  if [[ "${TAILSCALE_ENABLE}" != "true" ]]; then
    log_info "[tailscale] TAILSCALE_ENABLE=false; skipping tailscale setup"
    return 0
  fi

  log_info "[tailscale] configuring tailscale baseline"

  tailscale_install_repo
  tailscale_install_package
  tailscale_enable_service
  tailscale_connect

  log_info "[tailscale] tailscale baseline complete"
}
