#!/usr/bin/env bash

apps_run_root() {
  if (( EUID == 0 )); then
    run_cmd "$@"
    return 0
  fi

  command_exists sudo || die "[apps] sudo is required when not running as root"
  run_cmd sudo "$@"
}

apps_write_content_if_changed() {
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
    log_info "[apps] no changes for ${target}"
    rm -f "${tmp_file}"
    return 1
  fi

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[apps] [dry-run] would update ${target}"
    rm -f "${tmp_file}"
    return 0
  fi

  apps_run_root install -d -m 0755 "$(dirname "${target}")"
  apps_run_root cp "${tmp_file}" "${target}"
  apps_run_root chown root:root "${target}"
  apps_run_root chmod "${mode}" "${target}"
  rm -f "${tmp_file}"
  return 0
}

apps_render_compose_skeleton() {
  cat <<EOF
services: {}

networks:
  ${EDGE_NETWORK_NAME}:
    external: true
    name: ${EDGE_NETWORK_NAME}
EOF
}

apps_render_register_script() {
  cat <<EOF
#!/usr/bin/env python3
import os
import sys
from ruamel.yaml import YAML

yaml = YAML()
yaml.preserve_quotes = True

COMPOSE_PATH = "${APPS_COMPOSE_FILE}"
APPS_ROOT = "${APPS_ROOT_DIR}"
EDGE_NETWORK_NAME = "${EDGE_NETWORK_NAME}"
RESERVED_BOT_NAME = os.environ.get("BOT_NAME", "${BOT_NAME}")

def die(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)

def main() -> None:
    app_name = os.environ.get("APP_NAME")
    app_port = os.environ.get("APP_PORT")
    apps_domain = os.environ.get("APPS_DOMAIN", "${APPS_DOMAIN}")

    if not app_name:
        die("APP_NAME env var required")

    if not app_port or not app_port.isdigit():
        die("APP_PORT env var required and must be numeric")

    if not apps_domain:
        die("APPS_DOMAIN env var required")

    if app_name in {"traefik", RESERVED_BOT_NAME}:
        die(f"Reserved app name: {app_name}")

    if not (1 <= int(app_port) <= 65535):
        die("APP_PORT must be between 1 and 65535")

    app_dir = f"{APPS_ROOT}/{app_name}"
    os.makedirs(app_dir, exist_ok=True)

    if os.path.exists(COMPOSE_PATH):
        with open(COMPOSE_PATH, "r", encoding="utf-8") as f:
            doc = yaml.load(f) or {}
    else:
        doc = {}

    services = doc.setdefault("services", {})
    networks = doc.setdefault("networks", {})
    networks.setdefault(EDGE_NETWORK_NAME, {"external": True, "name": EDGE_NETWORK_NAME})

    host = f"{app_name}.{apps_domain}"
    services[app_name] = {
        "build": app_dir,
        "restart": "unless-stopped",
        "networks": [EDGE_NETWORK_NAME],
        "labels": [
            "traefik.enable=true",
            f"traefik.docker.network={EDGE_NETWORK_NAME}",
            f"traefik.http.routers.{app_name}.rule=Host(\`{host}\`)",
            f"traefik.http.routers.{app_name}.entrypoints=web",
            f"traefik.http.services.{app_name}.loadbalancer.server.port={app_port}",
        ],
    }

    with open(COMPOSE_PATH, "w", encoding="utf-8") as f:
        yaml.dump(doc, f)

    print(f"OK: registered {app_name} -> https://{host} (port {app_port})")
    print(f"APP_DIR={app_dir}")
    print(f"APP_URL=https://{host}")

if __name__ == "__main__":
    main()
EOF
}

apps_render_deploy_script() {
  cat <<EOF
#!/usr/bin/env bash
set -euo pipefail

APP_NAME="\${1:?app name required}"
APP_PORT="\${2:?internal port required (e.g. 3000)}"

export APP_NAME APP_PORT
export APPS_DOMAIN="\${APPS_DOMAIN:-${APPS_DOMAIN}}"
export BOT_NAME="\${BOT_NAME:-${BOT_NAME}}"

REGISTER_PY="${APPS_REGISTER_SCRIPT}"
ENSURE_WILDCARD_SH="${DNS_BIN_DIR}/cf_dns_ensure_wildcard.sh"
UPSERT_SUBDOMAIN_SH="${DNS_BIN_DIR}/cf_dns_upsert_subdomain.sh"
APPS_COMPOSE_FILE="${APPS_COMPOSE_FILE}"
APPS_VENV_DIR="${APPS_VENV_DIR}"
EDGE_NETWORK_NAME="${EDGE_NETWORK_NAME}"

if [[ -x "\${APPS_VENV_DIR}/bin/python" ]]; then
  "\${APPS_VENV_DIR}/bin/python" "\${REGISTER_PY}"
else
  python3 "\${REGISTER_PY}"
fi

if [[ -n "\${CF_API_TOKEN:-}" && -n "\${CF_ZONE_ID:-}" && -n "\${TUNNEL_UUID:-}" ]]; then
  if ! "\${ENSURE_WILDCARD_SH}" >/dev/null 2>&1; then
    export HOSTNAME="\${APP_NAME}.\${APPS_DOMAIN}"
    "\${UPSERT_SUBDOMAIN_SH}"
  fi
fi

docker compose -f "\${APPS_COMPOSE_FILE}" up -d --build "\${APP_NAME}"
docker compose -f "\${APPS_COMPOSE_FILE}" ps "\${APP_NAME}"

URL="https://\${APP_NAME}.\${APPS_DOMAIN}"
echo "DEPLOYED_URL=\${URL}"
EOF
}

apps_ensure_layout() {
  apps_run_root install -d -m 0755 "${APPS_ROOT_DIR}"
  apps_run_root install -d -m 0755 "$(dirname "${APPS_REGISTER_SCRIPT}")"
}

apps_setup_venv_if_enabled() {
  if [[ "${APPS_SETUP_VENV}" != "true" ]]; then
    log_info "[apps] APPS_SETUP_VENV=false; skipping virtualenv setup"
    return 0
  fi

  log_info "[apps] ensuring Python venv for app registry helper"
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    apps_run_root "${APPS_VENV_PYTHON}" -m venv "${APPS_VENV_DIR}"
    apps_run_root "${APPS_VENV_DIR}/bin/pip" install --upgrade pip
    apps_run_root "${APPS_VENV_DIR}/bin/pip" install ruamel.yaml
    return 0
  fi

  if [[ ! -x "${APPS_VENV_DIR}/bin/python" ]]; then
    apps_run_root "${APPS_VENV_PYTHON}" -m venv "${APPS_VENV_DIR}"
  fi

  if ! "${APPS_VENV_DIR}/bin/python" -c 'import ruamel.yaml' >/dev/null 2>&1; then
    apps_run_root "${APPS_VENV_DIR}/bin/pip" install --upgrade pip
    apps_run_root "${APPS_VENV_DIR}/bin/pip" install ruamel.yaml
  fi
}

apps_write_runtime_files() {
  local compose_skeleton
  local register_script
  local deploy_script

  compose_skeleton="$(apps_render_compose_skeleton)"
  register_script="$(apps_render_register_script)"
  deploy_script="$(apps_render_deploy_script)"

  apps_write_content_if_changed "${APPS_COMPOSE_FILE}" "0644" "${compose_skeleton}" || true
  apps_write_content_if_changed "${APPS_REGISTER_SCRIPT}" "0755" "${register_script}" || true
  apps_write_content_if_changed "${APPS_DEPLOY_SCRIPT}" "0755" "${deploy_script}" || true
}

phase_apps() {
  if [[ "${APPS_ENABLE}" != "true" ]]; then
    log_info "[apps] APPS_ENABLE=false; skipping apps registry setup"
    return 0
  fi

  log_info "[apps] configuring apps registry and helper scripts"
  apps_ensure_layout
  apps_setup_venv_if_enabled
  apps_write_runtime_files
  log_info "[apps] apps registry setup complete"
}
