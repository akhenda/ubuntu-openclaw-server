#!/usr/bin/env bash

packages_resolve_arch() {
  local arch=""

  if [[ -n "${DOCKER_ARCH:-}" ]]; then
    printf '%s' "${DOCKER_ARCH}"
    return 0
  fi

  if command_exists dpkg; then
    arch="$(dpkg --print-architecture)"
  else
    case "$(uname -m)" in
      x86_64) arch="amd64" ;;
      aarch64|arm64) arch="arm64" ;;
      armv7l) arch="armhf" ;;
      *)
        die "Unable to resolve Docker architecture. Set DOCKER_ARCH explicitly."
        ;;
    esac
  fi

  printf '%s' "${arch}"
}

packages_require_supported_os() {
  local os_release_file="${OS_RELEASE_FILE:-/etc/os-release}"
  require_file "${os_release_file}"

  # shellcheck disable=SC1090
  source "${os_release_file}"

  [[ "${ID:-}" == "ubuntu" ]] || die "Unsupported OS ID '${ID:-unknown}'. Ubuntu 24.04 is required."
  [[ "${VERSION_ID:-}" == "24.04" ]] || die "Unsupported Ubuntu version '${VERSION_ID:-unknown}'. Ubuntu 24.04 is required."
  [[ -n "${VERSION_CODENAME:-}" ]] || VERSION_CODENAME="noble"
}

packages_run_root() {
  if (( EUID == 0 )); then
    run_cmd "$@"
    return $?
  fi

  command_exists sudo || die "This phase requires root privileges (or sudo)."
  run_cmd sudo "$@"
}

packages_apt_with_retry() {
  local max_attempts="${APT_RETRY_ATTEMPTS:-20}"
  local sleep_seconds="${APT_RETRY_DELAY_SECONDS:-5}"
  local attempt=1

  while true; do
    if packages_run_root env DEBIAN_FRONTEND=noninteractive "$@"; then
      return 0
    fi

    if (( attempt >= max_attempts )); then
      return 1
    fi

    log_warn "[packages] apt command failed (attempt ${attempt}/${max_attempts}); retrying in ${sleep_seconds}s"
    attempt=$((attempt + 1))
    sleep "${sleep_seconds}"
  done
}

packages_write_docker_repo() {
  local repo_file="/etc/apt/sources.list.d/docker.list"
  local arch="$1"
  local codename="$2"
  local repo_line="deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${codename} stable"

  if [[ -f "${repo_file}" ]]; then
    local existing
    existing="$(cat "${repo_file}")"
    if [[ "${existing}" == "${repo_line}" ]]; then
      log_info "[packages] Docker apt repository already configured"
      return 0
    fi
  fi

  log_info "[packages] Configuring Docker apt repository"
  packages_run_root /bin/sh -c "printf '%s\n' \"${repo_line}\" > ${repo_file}"
}

phase_packages() {
  log_info "[packages] installing host prerequisites"
  packages_require_supported_os

  local docker_arch
  docker_arch="$(packages_resolve_arch)"
  local docker_codename="${VERSION_CODENAME:-noble}"

  log_info "[packages] Installing prerequisite OS packages"
  packages_apt_with_retry apt-get update
  packages_apt_with_retry apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    jq \
    apache2-utils \
    python3 \
    python3-venv \
    ufw \
    fail2ban \
    unattended-upgrades

  log_info "[packages] Installing Docker Engine from official repository"
  packages_run_root install -m 0755 -d /etc/apt/keyrings
  packages_run_root curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  packages_run_root chmod a+r /etc/apt/keyrings/docker.asc
  packages_write_docker_repo "${docker_arch}" "${docker_codename}"

  packages_apt_with_retry apt-get update
  packages_apt_with_retry apt-get install -y --no-install-recommends \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

  if command_exists systemctl; then
    packages_run_root systemctl enable --now docker
  else
    log_warn "[packages] systemctl not available; skipping docker service enablement"
  fi

  if command_exists docker; then
    log_info "[packages] $(docker --version)"
  fi

  if command_exists docker && docker compose version >/dev/null 2>&1; then
    log_info "[packages] $(docker compose version)"
  fi

  log_info "[packages] prerequisites complete"
}
