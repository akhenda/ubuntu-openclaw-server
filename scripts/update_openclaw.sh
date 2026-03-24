#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/common.sh"

CONFIG_FILE="${REPO_ROOT}/config/.env"
PRINT_CONFIG=true
DRY_RUN=false
DO_PULL=false

usage() {
  cat <<USAGE
Usage: $0 [options]

Update OpenClaw on the host using this repository's installer and config.

Options:
  --config <path>     Path to env config file (default: config/.env)
  --pull              Fast-forward this git checkout before reinstalling
  --no-print-config   Skip installer config summary output
  --dry-run           Show planned actions without mutating
  -h, --help          Show this help

Examples:
  $0
  $0 --pull
  $0 --config config/.env --pull
USAGE
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)
        [[ $# -ge 2 ]] || die "--config requires a value"
        CONFIG_FILE="$2"
        shift 2
        ;;
      --pull)
        DO_PULL=true
        shift
        ;;
      --no-print-config)
        PRINT_CONFIG=false
        shift
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done
}

ensure_clean_worktree_for_pull() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    return 0
  fi

  if ! git -C "${REPO_ROOT}" diff --quiet || ! git -C "${REPO_ROOT}" diff --cached --quiet; then
    die "Git worktree has uncommitted changes. Commit/stash them or rerun without --pull."
  fi
}

run_git_pull() {
  ensure_clean_worktree_for_pull
  run_cmd git -C "${REPO_ROOT}" pull --ff-only
}

run_installer() {
  local -a cmd=(bash "${REPO_ROOT}/scripts/install.sh" --config "${CONFIG_FILE}")
  if [[ "${PRINT_CONFIG}" == "true" ]]; then
    cmd+=(--print-config)
  fi
  if [[ "${DRY_RUN}" == "true" ]]; then
    cmd+=(--dry-run)
  fi
  run_cmd "${cmd[@]}"
}

post_update_summary() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[update] dry-run complete"
    return 0
  fi

  if command_exists openclaw; then
    log_info "[update] installed OpenClaw version:"
    openclaw --version || true
  else
    log_warn "[update] openclaw command not found after update"
  fi

  if command_exists systemctl; then
    log_info "[update] openclaw-gateway.service state:"
    systemctl status openclaw-gateway --no-pager -l | sed -n '1,20p' || true
  fi
}

main() {
  parse_args "$@"

  require_file "${CONFIG_FILE}"

  log_info "[update] repo root: ${REPO_ROOT}"
  log_info "[update] config file: ${CONFIG_FILE}"

  if [[ "${DO_PULL}" == "true" ]]; then
    log_info "[update] refreshing repository with git pull --ff-only"
    run_git_pull
  else
    log_info "[update] using current checked-out repository state"
  fi

  run_cmd bash "${REPO_ROOT}/scripts/install.sh" --check-config --config "${CONFIG_FILE}"
  run_installer
  post_update_summary
}

main "$@"
