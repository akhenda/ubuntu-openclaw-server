#!/usr/bin/env bash

apps_run_root() {
  if (( EUID == 0 )); then
    run_cmd "$@"
    return $?
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
import hashlib
from ruamel.yaml import YAML

yaml = YAML()
yaml.preserve_quotes = True

COMPOSE_PATH = "${APPS_COMPOSE_FILE}"
APPS_ROOT = "${APPS_ROOT_DIR}"
EDGE_NETWORK_NAME = "${EDGE_NETWORK_NAME}"
RESERVED_BOT_NAME = os.environ.get("BOT_NAME", "${BOT_NAME}")
HUB_SERVICE_NAME = "hub"

def die(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)

def icon_for_app(app_name: str) -> str:
    icons = [
        "mdi-rocket-launch",
        "mdi-cloud-outline",
        "mdi-code-braces",
        "mdi-cube-outline",
        "mdi-atom-variant",
        "mdi-lightning-bolt",
        "mdi-server-network",
        "mdi-monitor-dashboard",
    ]
    digest = hashlib.sha256(app_name.encode("utf-8")).hexdigest()
    index = int(digest[:8], 16) % len(icons)
    return icons[index]

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

    if app_name in {"traefik", RESERVED_BOT_NAME, HUB_SERVICE_NAME}:
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
            "homepage.group=Apps",
            f"homepage.name={app_name}",
            f"homepage.icon={icon_for_app(app_name)}",
            f"homepage.href=https://{host}",
            f"homepage.description={app_name} app on {host}",
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

apps_render_ensure_hub_script() {
  cat <<EOF
#!/usr/bin/env bash
set -euo pipefail

APPS_COMPOSE_FILE="\${APPS_COMPOSE_FILE:-${APPS_COMPOSE_FILE}}"
APPS_ROOT_DIR="\${APPS_ROOT_DIR:-${APPS_ROOT_DIR}}"
APPS_VENV_DIR="\${APPS_VENV_DIR:-${APPS_VENV_DIR}}"
EDGE_NETWORK_NAME="\${EDGE_NETWORK_NAME:-${EDGE_NETWORK_NAME}}"
HUB_PRIMARY_HOST="\${HUB_PRIMARY_HOST:-${HUB_PRIMARY_HOST}}"
HUB_ALIAS_HOST="\${HUB_ALIAS_HOST:-${HUB_ALIAS_HOST}}"
HUB_STYLE_PROFILE="\${HUB_STYLE_PROFILE:-${HUB_STYLE_PROFILE}}"
SOCKET_PROXY_ENDPOINT="\${SOCKET_PROXY_ENDPOINT:-${SOCKET_PROXY_ENDPOINT}}"
HUB_SERVICE_NAME="hub"
HUB_IMAGE="ghcr.io/gethomepage/homepage:latest"
HUB_CONFIG_DIR="\${APPS_ROOT_DIR}/hub-config"

mkdir -p "\${HUB_CONFIG_DIR}"
cat > "\${HUB_CONFIG_DIR}/settings.yaml" <<SETTINGS
title: OpenClaw Hub
layout:
  Apps:
    style: row
    columns: 4
background:
  image: https://images.unsplash.com/photo-1523966211575-eb4a01e7dd51?auto=format&fit=crop&w=1600&q=80
  blur: sm
color: slate
theme: dark
headerStyle: boxedWidgets
SETTINGS

cat > "\${HUB_CONFIG_DIR}/widgets.yaml" <<WIDGETS
- resources:
    cpu: true
    memory: true
    disk: /
- openmeteo:
    label: Nairobi
    latitude: -1.2864
    longitude: 36.8172
    timezone: Africa/Nairobi
WIDGETS

cat > "\${HUB_CONFIG_DIR}/docker.yaml" <<DOCKER
local:
  host: \${SOCKET_PROXY_ENDPOINT}
DOCKER

if [[ ! -f "\${APPS_COMPOSE_FILE}" ]]; then
  cat > "\${APPS_COMPOSE_FILE}" <<COMPOSE
services: {}

networks:
  \${EDGE_NETWORK_NAME}:
    external: true
    name: \${EDGE_NETWORK_NAME}
COMPOSE
fi

PYTHON_BIN="python3"
if [[ -x "\${APPS_VENV_DIR}/bin/python" ]]; then
  PYTHON_BIN="\${APPS_VENV_DIR}/bin/python"
fi

export APPS_COMPOSE_FILE EDGE_NETWORK_NAME HUB_PRIMARY_HOST HUB_ALIAS_HOST HUB_SERVICE_NAME HUB_IMAGE HUB_CONFIG_DIR
"\${PYTHON_BIN}" - <<'PY'
import os
from ruamel.yaml import YAML

compose_path = os.environ["APPS_COMPOSE_FILE"]
edge_network_name = os.environ["EDGE_NETWORK_NAME"]
hub_primary_host = os.environ["HUB_PRIMARY_HOST"]
hub_alias_host = os.environ.get("HUB_ALIAS_HOST", "").strip()
hub_service_name = os.environ["HUB_SERVICE_NAME"]
hub_image = os.environ["HUB_IMAGE"]
hub_config_dir = os.environ["HUB_CONFIG_DIR"]

yaml = YAML()
yaml.preserve_quotes = True

if os.path.exists(compose_path):
    with open(compose_path, "r", encoding="utf-8") as f:
        doc = yaml.load(f) or {}
else:
    doc = {}

services = doc.setdefault("services", {})
networks = doc.setdefault("networks", {})
networks.setdefault(edge_network_name, {"external": True, "name": edge_network_name})

route_hosts = [hub_primary_host]
if hub_alias_host and hub_alias_host != hub_primary_host:
    route_hosts.append(hub_alias_host)

host_match = " || ".join([f'Host("{host}")' for host in route_hosts])
allowed_hosts = ",".join(route_hosts)

services[hub_service_name] = {
    "image": hub_image,
    "restart": "unless-stopped",
    "networks": [edge_network_name],
    "volumes": [
        f"{hub_config_dir}:/app/config",
    ],
    "environment": {
        "HOMEPAGE_ALLOWED_HOSTS": allowed_hosts,
    },
    "labels": [
        "traefik.enable=true",
        f"traefik.docker.network={edge_network_name}",
        f"traefik.http.routers.hub.rule={host_match}",
        "traefik.http.routers.hub.entrypoints=web",
        "traefik.http.services.hub.loadbalancer.server.port=3000",
    ],
}

with open(compose_path, "w", encoding="utf-8") as f:
    yaml.dump(doc, f)

print(f"OK: ensured hub service routes -> {', '.join(route_hosts)}")
PY

docker compose -f "\${APPS_COMPOSE_FILE}" up -d "\${HUB_SERVICE_NAME}"
docker compose -f "\${APPS_COMPOSE_FILE}" ps "\${HUB_SERVICE_NAME}"
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
ENSURE_HUB_SH="${DNS_BIN_DIR}/ensure_hub.sh"
APPS_COMPOSE_FILE="${APPS_COMPOSE_FILE}"
APPS_VENV_DIR="${APPS_VENV_DIR}"
EDGE_NETWORK_NAME="${EDGE_NETWORK_NAME}"
HUB_ENABLE="\${HUB_ENABLE:-${HUB_ENABLE}}"
HUB_AUTOCREATE_ON_FIRST_APP="\${HUB_AUTOCREATE_ON_FIRST_APP:-${HUB_AUTOCREATE_ON_FIRST_APP}}"
HUB_PRIMARY_HOST="\${HUB_PRIMARY_HOST:-${HUB_PRIMARY_HOST}}"
HUB_ALIAS_HOST="\${HUB_ALIAS_HOST:-${HUB_ALIAS_HOST}}"
HUB_STYLE_PROFILE="\${HUB_STYLE_PROFILE:-${HUB_STYLE_PROFILE}}"

if [[ -x "\${APPS_VENV_DIR}/bin/python" ]]; then
  "\${APPS_VENV_DIR}/bin/python" "\${REGISTER_PY}"
else
  python3 "\${REGISTER_PY}"
fi

if [[ "\${HUB_ENABLE}" == "true" && "\${HUB_AUTOCREATE_ON_FIRST_APP}" == "true" ]]; then
  "\${ENSURE_HUB_SH}"
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
  local ensure_hub_script
  local deploy_script

  compose_skeleton="$(apps_render_compose_skeleton)"
  register_script="$(apps_render_register_script)"
  ensure_hub_script="$(apps_render_ensure_hub_script)"
  deploy_script="$(apps_render_deploy_script)"

  apps_write_content_if_changed "${APPS_COMPOSE_FILE}" "0644" "${compose_skeleton}" || true
  apps_write_content_if_changed "${APPS_REGISTER_SCRIPT}" "0755" "${register_script}" || true
  apps_write_content_if_changed "${DNS_BIN_DIR}/ensure_hub.sh" "0755" "${ensure_hub_script}" || true
  apps_write_content_if_changed "${APPS_DEPLOY_SCRIPT}" "0755" "${deploy_script}" || true
}

apps_ensure_hub_during_install() {
  if [[ "${HUB_ENABLE}" != "true" ]]; then
    return 0
  fi

  log_info "[apps] ensuring hub service exists during install"
  apps_run_root /bin/bash "${DNS_BIN_DIR}/ensure_hub.sh"
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
  apps_ensure_hub_during_install
  log_info "[apps] apps registry setup complete"
}
