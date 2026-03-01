#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

for module in \
  common.sh \
  config.sh \
  packages.sh \
  user.sh \
  ssh.sh \
  firewall.sh \
  edge.sh \
  dns.sh \
  openclaw.sh \
  apps.sh \
  report.sh \
  verify.sh
  do
  # shellcheck source=/dev/null
  source "${LIB_DIR}/${module}"
done

CONFIG_FILE="${REPO_ROOT}/config/.env"
CHECK_CONFIG=false
PRINT_CONFIG=false
DRY_RUN=false

usage() {
  cat <<USAGE
Usage: $0 [options]

Options:
  --config <path>     Path to env config file (default: config/.env)
  --check-config      Validate config and exit
  --print-config      Print effective config summary after validation
  --dry-run           Enable dry-run mode for future mutating phases
  -h, --help          Show this help

Examples:
  $0 --check-config --config config/.env
  $0 --config config/.env --print-config
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
      --check-config)
        CHECK_CONFIG=true
        shift
        ;;
      --print-config)
        PRINT_CONFIG=true
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

main() {
  parse_args "$@"

  log_info "OpenClaw Bash toolkit scaffold"
  log_info "Repo root: ${REPO_ROOT}"

  load_config_file "${CONFIG_FILE}"
  set_default_config
  validate_config

  if [[ "${PRINT_CONFIG}" == "true" ]]; then
    print_config_summary
  fi

  if [[ "${CHECK_CONFIG}" == "true" ]]; then
    log_info "Config check completed successfully"
    exit 0
  fi

  log_warn "Scaffold mode: phase implementations are placeholders in this commit"

  phase_packages
  phase_user
  phase_ssh
  phase_firewall
  phase_edge
  phase_dns
  phase_openclaw
  phase_apps
  phase_report
  phase_verify

  log_info "Scaffold execution completed"
  log_info "Next: implement real phase logic incrementally"
}

main "$@"
