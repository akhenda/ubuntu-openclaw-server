#!/usr/bin/env bash

report_run_root() {
  if (( EUID == 0 )); then
    run_cmd "$@"
    return $?
  fi

  command_exists sudo || die "[report] sudo is required when not running as root"
  run_cmd sudo "$@"
}

report_write_content_if_changed() {
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
    log_info "[report] no changes for ${target}"
    rm -f "${tmp_file}"
    return 1
  fi

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[report] [dry-run] would update ${target}"
    rm -f "${tmp_file}"
    return 0
  fi

  report_run_root install -d -m 0755 "$(dirname "${target}")"
  report_run_root cp "${tmp_file}" "${target}"
  report_run_root chown root:root "${target}"
  report_run_root chmod "${mode}" "${target}"
  rm -f "${tmp_file}"
  return 0
}

report_render_script() {
  cat <<EOF
#!/usr/bin/env bash
set -euo pipefail

TITLE="\${1:?title required}"
BODY="\${2:?body required}"

DEFAULT_REPORT_OWNER_NAME="${REPORT_OWNER_NAME}"
DEFAULT_REPORT_FAIL_ON_SEND="${REPORT_FAIL_ON_SEND}"
DEFAULT_OPENCLAW_WRAPPER="${OPENCLAW_WRAPPER_PATH:-/usr/local/bin/openclaw}"
DEFAULT_RUNTIME_USER="${RUNTIME_USER}"
DEFAULT_RUNTIME_HOME="${OPENCLAW_RUNTIME_HOME}"
DEFAULT_OPENCLAW_BIN="${OPENCLAW_BIN}"

REPORT_OWNER_NAME="\${REPORT_OWNER_NAME:-\${DEFAULT_REPORT_OWNER_NAME}}"
REPORT_FAIL_ON_SEND="\${REPORT_FAIL_ON_SEND:-\${DEFAULT_REPORT_FAIL_ON_SEND}}"
REPORT_CHANNEL="\${REPORT_CHANNEL:-}"
REPORT_TARGET="\${REPORT_TARGET:-}"
OPENCLAW_WRAPPER="\${OPENCLAW_WRAPPER:-\${DEFAULT_OPENCLAW_WRAPPER}}"
RUNTIME_USER="\${RUNTIME_USER:-\${DEFAULT_RUNTIME_USER}}"
RUNTIME_HOME="\${RUNTIME_HOME:-\${DEFAULT_RUNTIME_HOME}}"
OPENCLAW_BIN="\${OPENCLAW_BIN:-\${DEFAULT_OPENCLAW_BIN}}"

fallback_stdout() {
  echo "=== \${TITLE} (owner: \${REPORT_OWNER_NAME}) ==="
  echo "\${BODY}"
}

fail_or_fallback() {
  local reason="\$1"
  echo "WARN: \${reason}" >&2
  if [[ "\${REPORT_FAIL_ON_SEND}" == "true" ]]; then
    return 1
  fi
  fallback_stdout
  return 0
}

if [[ -z "\${REPORT_TARGET}" ]]; then
  fallback_stdout
  exit 0
fi

if [[ ! -x "\${OPENCLAW_WRAPPER}" ]]; then
  fail_or_fallback "OpenClaw wrapper not found: \${OPENCLAW_WRAPPER}"
  exit \$?
fi

message="\${TITLE}\n\n\${BODY}"
if [[ -n "\${REPORT_CHANNEL}" ]]; then
  if ! "\${OPENCLAW_WRAPPER}" message send --channel "\${REPORT_CHANNEL}" --target "\${REPORT_TARGET}" --message "\${message}"; then
    fail_or_fallback "OpenClaw message send failed"
    exit \$?
  fi
else
  if ! "\${OPENCLAW_WRAPPER}" message send --target "\${REPORT_TARGET}" --message "\${message}"; then
    fail_or_fallback "OpenClaw message send failed"
    exit \$?
  fi
fi
EOF
}

phase_report() {
  if [[ "${REPORT_ENABLE}" != "true" ]]; then
    log_info "[report] REPORT_ENABLE=false; skipping report helper setup"
    return 0
  fi

  log_info "[report] configuring deployment report helper"
  local script_content
  script_content="$(report_render_script)"
  report_write_content_if_changed "${REPORT_SCRIPT}" "0755" "${script_content}" || true

  if [[ -z "${REPORT_TARGET:-}" ]]; then
    log_warn "[report] REPORT_TARGET is not set; generated helper will fallback to stdout."
  fi

  log_info "[report] report helper setup complete"
}
