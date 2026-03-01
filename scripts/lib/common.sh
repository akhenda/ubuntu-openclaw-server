#!/usr/bin/env bash

# Shared logging and utility helpers for the Bash toolkit.

log_ts() {
  date +"%Y-%m-%dT%H:%M:%S%z"
}

log_info() {
  printf '[%s] [INFO] %s\n' "$(log_ts)" "$*"
}

log_warn() {
  printf '[%s] [WARN] %s\n' "$(log_ts)" "$*" >&2
}

log_error() {
  printf '[%s] [ERROR] %s\n' "$(log_ts)" "$*" >&2
}

die() {
  log_error "$*"
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || die "Required file not found: $path"
}

redact_secret() {
  local value="${1:-}"
  local len="${#value}"

  if (( len == 0 )); then
    printf '<empty>'
    return 0
  fi

  if (( len <= 8 )); then
    printf '****'
    return 0
  fi

  printf '%s****%s' "${value:0:4}" "${value: -4}"
}

run_cmd() {
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[dry-run] $*"
    return 0
  fi

  log_info "Running: $*"
  "$@"
}

validate_ipv4() {
  local ip="$1"
  local IFS='.'
  local -a octets=()
  read -r -a octets <<< "$ip"

  [[ ${#octets[@]} -eq 4 ]] || return 1

  local octet
  for octet in "${octets[@]}"; do
    [[ "$octet" =~ ^[0-9]+$ ]] || return 1
    (( octet >= 0 && octet <= 255 )) || return 1
  done

  return 0
}
