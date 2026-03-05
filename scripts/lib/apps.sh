#!/usr/bin/env bash

apps_run_root() {
  if (( EUID == 0 )); then
    run_cmd "$@"
    return $?
  fi

  command_exists sudo || die "[apps] sudo is required when not running as root"
  run_cmd sudo "$@"
}

apps_run_runtime() {
  if [[ "${USER:-}" == "${RUNTIME_USER}" ]]; then
    run_cmd "$@"
    return $?
  fi

  command_exists sudo || die "[apps] sudo is required to run commands as ${RUNTIME_USER}"
  run_cmd sudo -u "${RUNTIME_USER}" -H "$@"
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
MISSION_CONTROL_SERVICE_NAME = os.environ.get("MISSION_CONTROL_SERVICE_NAME", "${MISSION_CONTROL_SERVICE_NAME}")

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

    reserved_names = {"traefik", RESERVED_BOT_NAME, HUB_SERVICE_NAME}
    if MISSION_CONTROL_SERVICE_NAME:
        reserved_names.add(MISSION_CONTROL_SERVICE_NAME)

    if app_name in reserved_names:
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
MISSION_CONTROL_ENABLE="\${MISSION_CONTROL_ENABLE:-${MISSION_CONTROL_ENABLE}}"
MISSION_CONTROL_SERVICE_NAME="\${MISSION_CONTROL_SERVICE_NAME:-${MISSION_CONTROL_SERVICE_NAME}}"
MISSION_CONTROL_HOST="\${MISSION_CONTROL_HOST:-${MISSION_CONTROL_HOST}}"
MISSION_CONTROL_API_HOST="\${MISSION_CONTROL_API_HOST:-${MISSION_CONTROL_API_HOST}}"
MISSION_CONTROL_FRONTEND_DIR="\${MISSION_CONTROL_FRONTEND_DIR:-${MISSION_CONTROL_FRONTEND_DIR}}"
MISSION_CONTROL_SOURCE_DIR="\${MISSION_CONTROL_SOURCE_DIR:-${MISSION_CONTROL_SOURCE_DIR}}"
MISSION_CONTROL_AUTH_MODE="\${MISSION_CONTROL_AUTH_MODE:-${MISSION_CONTROL_AUTH_MODE}}"
MISSION_CONTROL_LOCAL_AUTH_TOKEN="\${MISSION_CONTROL_LOCAL_AUTH_TOKEN:-${MISSION_CONTROL_LOCAL_AUTH_TOKEN}}"
MISSION_CONTROL_DB_AUTO_MIGRATE="\${MISSION_CONTROL_DB_AUTO_MIGRATE:-${MISSION_CONTROL_DB_AUTO_MIGRATE}}"
MISSION_CONTROL_POSTGRES_DB="\${MISSION_CONTROL_POSTGRES_DB:-${MISSION_CONTROL_POSTGRES_DB}}"
MISSION_CONTROL_POSTGRES_USER="\${MISSION_CONTROL_POSTGRES_USER:-${MISSION_CONTROL_POSTGRES_USER}}"
MISSION_CONTROL_POSTGRES_PASSWORD="\${MISSION_CONTROL_POSTGRES_PASSWORD:-${MISSION_CONTROL_POSTGRES_PASSWORD}}"
MISSION_CONTROL_RQ_QUEUE_NAME="\${MISSION_CONTROL_RQ_QUEUE_NAME:-${MISSION_CONTROL_RQ_QUEUE_NAME}}"
MISSION_CONTROL_RQ_DISPATCH_THROTTLE_SECONDS="\${MISSION_CONTROL_RQ_DISPATCH_THROTTLE_SECONDS:-${MISSION_CONTROL_RQ_DISPATCH_THROTTLE_SECONDS}}"
MISSION_CONTROL_RQ_DISPATCH_MAX_RETRIES="\${MISSION_CONTROL_RQ_DISPATCH_MAX_RETRIES:-${MISSION_CONTROL_RQ_DISPATCH_MAX_RETRIES}}"
SOCKET_PROXY_ENDPOINT="\${SOCKET_PROXY_ENDPOINT:-${SOCKET_PROXY_ENDPOINT}}"
HUB_SERVICE_NAME="hub"
HUB_IMAGE="ghcr.io/gethomepage/homepage:latest"
HUB_CONFIG_DIR="\${APPS_ROOT_DIR}/hub-config"
SETTINGS_MARKER="# managed-by-openclaw-hub-style"
SOCKET_PROXY_PROTOCOL="http"
SOCKET_PROXY_ADDR="\${SOCKET_PROXY_ENDPOINT}"
if [[ "\${SOCKET_PROXY_ADDR}" == https://* ]]; then
  SOCKET_PROXY_PROTOCOL="https"
  SOCKET_PROXY_ADDR="\${SOCKET_PROXY_ADDR#https://}"
elif [[ "\${SOCKET_PROXY_ADDR}" == http://* ]]; then
  SOCKET_PROXY_ADDR="\${SOCKET_PROXY_ADDR#http://}"
fi
SOCKET_PROXY_HOST="\${SOCKET_PROXY_ADDR%%:*}"
SOCKET_PROXY_PORT="\${SOCKET_PROXY_ADDR##*:}"
if [[ -z "\${SOCKET_PROXY_HOST}" || -z "\${SOCKET_PROXY_PORT}" || ! "\${SOCKET_PROXY_PORT}" =~ ^[0-9]+$ ]]; then
  echo "Invalid SOCKET_PROXY_ENDPOINT (expected http[s]://host:port): \${SOCKET_PROXY_ENDPOINT}" >&2
  exit 1
fi

mkdir -p "\${HUB_CONFIG_DIR}"

write_settings_profile() {
  case "\${HUB_STYLE_PROFILE}" in
    modern-minimal)
      cat > "\${HUB_CONFIG_DIR}/settings.yaml" <<SETTINGS
\${SETTINGS_MARKER}
title: OpenClaw Hub
layout:
  Apps:
    style: row
    columns: 4
background:
  image: https://images.unsplash.com/photo-1523966211575-eb4a01e7dd51?auto=format&fit=crop&w=1600&q=80
  blur: sm
theme: dark
headerStyle: boxedWidgets
SETTINGS
      ;;
    minimal)
      cat > "\${HUB_CONFIG_DIR}/settings.yaml" <<SETTINGS
\${SETTINGS_MARKER}
title: OpenClaw Hub
layout:
  Apps:
    style: row
    columns: 4
theme: dark
headerStyle: clean
SETTINGS
      ;;
    creative-minimal)
      cat > "\${HUB_CONFIG_DIR}/settings.yaml" <<SETTINGS
\${SETTINGS_MARKER}
title: OpenClaw Hub
layout:
  Apps:
    style: row
    columns: 3
background:
  image: https://images.unsplash.com/photo-1518770660439-4636190af475?auto=format&fit=crop&w=1600&q=80
  blur: md
theme: dark
headerStyle: boxed
SETTINGS
      ;;
    *)
      echo "Unsupported HUB_STYLE_PROFILE: \${HUB_STYLE_PROFILE}" >&2
      exit 1
      ;;
  esac
}

if [[ ! -f "\${HUB_CONFIG_DIR}/settings.yaml" ]]; then
  write_settings_profile
elif grep -Fq "\${SETTINGS_MARKER}" "\${HUB_CONFIG_DIR}/settings.yaml"; then
  write_settings_profile
fi

if [[ ! -f "\${HUB_CONFIG_DIR}/widgets.yaml" ]]; then
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
fi

if [[ ! -f "\${HUB_CONFIG_DIR}/docker.yaml" ]]; then
cat > "\${HUB_CONFIG_DIR}/docker.yaml" <<DOCKER
local:
  host: \${SOCKET_PROXY_HOST}
  port: \${SOCKET_PROXY_PORT}
  protocol: \${SOCKET_PROXY_PROTOCOL}
DOCKER
fi

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
export MISSION_CONTROL_ENABLE MISSION_CONTROL_SERVICE_NAME MISSION_CONTROL_HOST MISSION_CONTROL_API_HOST
export MISSION_CONTROL_FRONTEND_DIR MISSION_CONTROL_SOURCE_DIR MISSION_CONTROL_AUTH_MODE
export MISSION_CONTROL_LOCAL_AUTH_TOKEN MISSION_CONTROL_DB_AUTO_MIGRATE
export MISSION_CONTROL_POSTGRES_DB MISSION_CONTROL_POSTGRES_USER MISSION_CONTROL_POSTGRES_PASSWORD
export MISSION_CONTROL_RQ_QUEUE_NAME MISSION_CONTROL_RQ_DISPATCH_THROTTLE_SECONDS MISSION_CONTROL_RQ_DISPATCH_MAX_RETRIES
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
mission_control_enabled = os.environ.get("MISSION_CONTROL_ENABLE", "false").strip().lower() == "true"
mission_control_service_name = os.environ.get("MISSION_CONTROL_SERVICE_NAME", "mission-control").strip() or "mission-control"
mission_control_host = os.environ.get("MISSION_CONTROL_HOST", "").strip()
mission_control_api_host = os.environ.get("MISSION_CONTROL_API_HOST", "").strip()
mission_control_frontend_dir = os.environ.get("MISSION_CONTROL_FRONTEND_DIR", "").strip()
mission_control_source_dir = os.environ.get("MISSION_CONTROL_SOURCE_DIR", "").strip()
mission_control_auth_mode = os.environ.get("MISSION_CONTROL_AUTH_MODE", "local").strip() or "local"
mission_control_local_auth_token = os.environ.get("MISSION_CONTROL_LOCAL_AUTH_TOKEN", "").strip()
mission_control_db_auto_migrate = os.environ.get("MISSION_CONTROL_DB_AUTO_MIGRATE", "true").strip().lower()
mission_control_postgres_db = os.environ.get("MISSION_CONTROL_POSTGRES_DB", "mission_control").strip() or "mission_control"
mission_control_postgres_user = os.environ.get("MISSION_CONTROL_POSTGRES_USER", "postgres").strip() or "postgres"
mission_control_postgres_password = os.environ.get("MISSION_CONTROL_POSTGRES_PASSWORD", "postgres").strip() or "postgres"
mission_control_rq_queue_name = os.environ.get("MISSION_CONTROL_RQ_QUEUE_NAME", "default").strip() or "default"
mission_control_rq_dispatch_throttle_seconds = os.environ.get("MISSION_CONTROL_RQ_DISPATCH_THROTTLE_SECONDS", "2.0").strip() or "2.0"
mission_control_rq_dispatch_max_retries = os.environ.get("MISSION_CONTROL_RQ_DISPATCH_MAX_RETRIES", "3").strip() or "3"
services_config_path = os.path.join(hub_config_dir, "services.yaml")

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

def labels_to_map(raw_labels):
    mapped = {}
    if isinstance(raw_labels, list):
        for item in raw_labels:
            if not isinstance(item, str) or "=" not in item:
                continue
            key, value = item.split("=", 1)
            mapped[key] = value
    elif isinstance(raw_labels, dict):
        for key, value in raw_labels.items():
            mapped[str(key)] = str(value)
    return mapped

def extract_host_from_rule(rule):
    if not isinstance(rule, str):
        return ""
    backtick = chr(96)
    backtick_marker = f"Host({backtick}"
    quote_marker = 'Host("'

    if backtick_marker in rule:
        return rule.split(backtick_marker, 1)[1].split(backtick, 1)[0]
    if quote_marker in rule:
        return rule.split(quote_marker, 1)[1].split('"', 1)[0]
    return ""

if mission_control_enabled:
    if not mission_control_host:
        raise SystemExit("MISSION_CONTROL_HOST must be set when MISSION_CONTROL_ENABLE=true")
    if not mission_control_api_host:
        raise SystemExit("MISSION_CONTROL_API_HOST must be set when MISSION_CONTROL_ENABLE=true")
    if not mission_control_frontend_dir:
        raise SystemExit("MISSION_CONTROL_FRONTEND_DIR must be set when MISSION_CONTROL_ENABLE=true")
    if not mission_control_source_dir:
        raise SystemExit("MISSION_CONTROL_SOURCE_DIR must be set when MISSION_CONTROL_ENABLE=true")
    if mission_control_auth_mode == "local" and len(mission_control_local_auth_token) < 50:
        raise SystemExit("MISSION_CONTROL_LOCAL_AUTH_TOKEN must be at least 50 chars when MISSION_CONTROL_AUTH_MODE=local")

    mission_control_internal_network = f"{mission_control_service_name}-internal"
    mission_control_db_service_name = f"{mission_control_service_name}-db"
    mission_control_redis_service_name = f"{mission_control_service_name}-redis"
    mission_control_backend_service_name = f"{mission_control_service_name}-backend"
    mission_control_worker_service_name = f"{mission_control_service_name}-webhook-worker"
    mission_control_volume_name = f"{mission_control_service_name}-postgres-data"
    mission_control_database_url = (
        f"postgresql+psycopg://{mission_control_postgres_user}:{mission_control_postgres_password}"
        f"@{mission_control_db_service_name}:5432/{mission_control_postgres_db}"
    )
    mission_control_redis_url = f"redis://{mission_control_redis_service_name}:6379/0"
    mission_control_api_base_url = f"https://{mission_control_api_host}"

    networks[mission_control_internal_network] = {}
    volumes = doc.setdefault("volumes", {})
    volumes.setdefault(mission_control_volume_name, {})

    mission_control_labels = [
        "traefik.enable=true",
        f"traefik.docker.network={edge_network_name}",
        f'traefik.http.routers.{mission_control_service_name}.rule=Host("{mission_control_host}")',
        f"traefik.http.routers.{mission_control_service_name}.entrypoints=web",
        f"traefik.http.services.{mission_control_service_name}.loadbalancer.server.port=3000",
        "homepage.group=Apps",
        "homepage.name=Mission Control",
        "homepage.icon=mdi-radar",
        f"homepage.href=https://{mission_control_host}",
        "homepage.description=Mission Control dashboard",
    ]

    mission_control_backend_labels = [
        "traefik.enable=true",
        f"traefik.docker.network={edge_network_name}",
        f'traefik.http.routers.{mission_control_backend_service_name}.rule=Host("{mission_control_api_host}")',
        f"traefik.http.routers.{mission_control_backend_service_name}.entrypoints=web",
        f"traefik.http.services.{mission_control_backend_service_name}.loadbalancer.server.port=8000",
    ]

    services[mission_control_db_service_name] = {
        "image": "postgres:16-alpine",
        "restart": "unless-stopped",
        "environment": {
            "POSTGRES_DB": mission_control_postgres_db,
            "POSTGRES_USER": mission_control_postgres_user,
            "POSTGRES_PASSWORD": mission_control_postgres_password,
        },
        "volumes": [f"{mission_control_volume_name}:/var/lib/postgresql/data"],
        "healthcheck": {
            "test": [
                "CMD-SHELL",
                f"pg_isready -U {mission_control_postgres_user} -d {mission_control_postgres_db}",
            ],
            "interval": "10s",
            "timeout": "5s",
            "retries": 5,
        },
        "networks": [mission_control_internal_network],
    }

    services[mission_control_redis_service_name] = {
        "image": "redis:7-alpine",
        "restart": "unless-stopped",
        "healthcheck": {
            "test": ["CMD", "redis-cli", "ping"],
            "interval": "10s",
            "timeout": "3s",
            "retries": 5,
        },
        "networks": [mission_control_internal_network],
    }

    services[mission_control_backend_service_name] = {
        "build": {
            "context": mission_control_source_dir,
            "dockerfile": "backend/Dockerfile",
        },
        "restart": "unless-stopped",
        "environment": {
            "DATABASE_URL": mission_control_database_url,
            "DB_AUTO_MIGRATE": mission_control_db_auto_migrate,
            "CORS_ORIGINS": f"https://{mission_control_host}",
            "AUTH_MODE": mission_control_auth_mode,
            "LOCAL_AUTH_TOKEN": mission_control_local_auth_token,
            "BASE_URL": mission_control_api_base_url,
            "RQ_REDIS_URL": mission_control_redis_url,
            "RQ_QUEUE_NAME": mission_control_rq_queue_name,
            "RQ_DISPATCH_THROTTLE_SECONDS": mission_control_rq_dispatch_throttle_seconds,
            "RQ_DISPATCH_MAX_RETRIES": mission_control_rq_dispatch_max_retries,
        },
        "depends_on": {
            mission_control_db_service_name: {"condition": "service_healthy"},
            mission_control_redis_service_name: {"condition": "service_healthy"},
        },
        "networks": [mission_control_internal_network, edge_network_name],
        "labels": mission_control_backend_labels,
    }

    mission_control_service = {
        "build": {
            "context": mission_control_frontend_dir,
        },
        "restart": "unless-stopped",
        "environment": {
            "VITE_API_BASE_URL": mission_control_api_base_url,
        },
        "depends_on": {
            mission_control_backend_service_name: {"condition": "service_started"},
        },
        "networks": [mission_control_internal_network, edge_network_name],
        "labels": mission_control_labels,
    }
    services[mission_control_service_name] = mission_control_service
    services[mission_control_worker_service_name] = {
        "build": {
            "context": mission_control_source_dir,
            "dockerfile": "backend/Dockerfile",
        },
        "restart": "unless-stopped",
        "command": ["python", "-m", "app.workers.webhook_worker"],
        "environment": {
            "DATABASE_URL": mission_control_database_url,
            "DB_AUTO_MIGRATE": "false",
            "CORS_ORIGINS": f"https://{mission_control_host}",
            "AUTH_MODE": mission_control_auth_mode,
            "LOCAL_AUTH_TOKEN": mission_control_local_auth_token,
            "BASE_URL": mission_control_api_base_url,
            "RQ_REDIS_URL": mission_control_redis_url,
            "RQ_QUEUE_NAME": mission_control_rq_queue_name,
            "RQ_DISPATCH_THROTTLE_SECONDS": mission_control_rq_dispatch_throttle_seconds,
            "RQ_DISPATCH_MAX_RETRIES": mission_control_rq_dispatch_max_retries,
        },
        "depends_on": {
            mission_control_db_service_name: {"condition": "service_healthy"},
            mission_control_redis_service_name: {"condition": "service_healthy"},
        },
        "networks": [mission_control_internal_network],
    }
else:
    mission_control_internal_network = f"{mission_control_service_name}-internal"
    mission_control_db_service_name = f"{mission_control_service_name}-db"
    mission_control_redis_service_name = f"{mission_control_service_name}-redis"
    mission_control_backend_service_name = f"{mission_control_service_name}-backend"
    mission_control_worker_service_name = f"{mission_control_service_name}-webhook-worker"
    mission_control_volume_name = f"{mission_control_service_name}-postgres-data"
    services.pop(mission_control_db_service_name, None)
    services.pop(mission_control_redis_service_name, None)
    services.pop(mission_control_backend_service_name, None)
    services.pop(mission_control_service_name, None)
    services.pop(mission_control_worker_service_name, None)
    networks.pop(mission_control_internal_network, None)
    if "volumes" in doc and isinstance(doc["volumes"], dict):
        doc["volumes"].pop(mission_control_volume_name, None)

grouped_services = {}
for service_name, service_cfg in services.items():
    if service_name == hub_service_name:
        continue

    labels = labels_to_map(service_cfg.get("labels", []))
    group_name = labels.get("homepage.group", "Apps").strip() or "Apps"
    display_name = labels.get("homepage.name", service_name).strip() or service_name
    description = labels.get("homepage.description", f"{display_name} app").strip()
    icon = labels.get("homepage.icon", "").strip()
    href = labels.get("homepage.href", "").strip()

    if not href:
        explicit_rule = labels.get(f"traefik.http.routers.{service_name}.rule", "")
        host = extract_host_from_rule(explicit_rule)
        if not host:
            for key, value in labels.items():
                if key.startswith("traefik.http.routers.") and key.endswith(".rule"):
                    host = extract_host_from_rule(value)
                    if host:
                        break
        if host:
            href = f"https://{host}"

    item_meta = {}
    if icon:
        item_meta["icon"] = icon
    if href:
        item_meta["href"] = href
    if description:
        item_meta["description"] = description

    grouped_services.setdefault(group_name, []).append({display_name: item_meta})

services_doc = []
if grouped_services:
    for group_name in sorted(grouped_services.keys(), key=lambda v: v.lower()):
        entries = grouped_services[group_name]
        entries.sort(key=lambda item: next(iter(item)).lower())
        services_doc.append({group_name: entries})
else:
    services_doc = [
        {
            "Apps": [
                {
                    "No apps yet": {
                        "icon": "mdi-rocket-launch",
                        "description": "Deploy your first app to populate the hub.",
                    }
                }
            ]
        }
    ]

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

with open(services_config_path, "w", encoding="utf-8") as f:
    yaml.dump(services_doc, f)

print(f"OK: ensured hub service routes -> {', '.join(route_hosts)}")
if mission_control_enabled:
    print(f"OK: ensured mission control routes -> {mission_control_host}, {mission_control_api_host}")
print(f"OK: wrote hub services catalog -> {services_config_path}")
PY

PROJECT_DIR="\$(dirname "\${APPS_COMPOSE_FILE}")"
docker compose --project-directory "\${PROJECT_DIR}" -f "\${APPS_COMPOSE_FILE}" up -d "\${HUB_SERVICE_NAME}"
docker compose --project-directory "\${PROJECT_DIR}" -f "\${APPS_COMPOSE_FILE}" ps "\${HUB_SERVICE_NAME}"
if [[ "\${MISSION_CONTROL_ENABLE}" == "true" ]]; then
  MISSION_CONTROL_DB_SERVICE_NAME="\${MISSION_CONTROL_SERVICE_NAME}-db"
  MISSION_CONTROL_REDIS_SERVICE_NAME="\${MISSION_CONTROL_SERVICE_NAME}-redis"
  MISSION_CONTROL_BACKEND_SERVICE_NAME="\${MISSION_CONTROL_SERVICE_NAME}-backend"
  MISSION_CONTROL_WORKER_SERVICE_NAME="\${MISSION_CONTROL_SERVICE_NAME}-webhook-worker"
  docker compose --project-directory "\${PROJECT_DIR}" -f "\${APPS_COMPOSE_FILE}" up -d \
    "\${MISSION_CONTROL_DB_SERVICE_NAME}" \
    "\${MISSION_CONTROL_REDIS_SERVICE_NAME}" \
    "\${MISSION_CONTROL_BACKEND_SERVICE_NAME}" \
    "\${MISSION_CONTROL_SERVICE_NAME}" \
    "\${MISSION_CONTROL_WORKER_SERVICE_NAME}"
  docker compose --project-directory "\${PROJECT_DIR}" -f "\${APPS_COMPOSE_FILE}" ps \
    "\${MISSION_CONTROL_DB_SERVICE_NAME}" \
    "\${MISSION_CONTROL_REDIS_SERVICE_NAME}" \
    "\${MISSION_CONTROL_BACKEND_SERVICE_NAME}" \
    "\${MISSION_CONTROL_SERVICE_NAME}" \
    "\${MISSION_CONTROL_WORKER_SERVICE_NAME}"
fi
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
PROJECT_DIR="\$(dirname "\${APPS_COMPOSE_FILE}")"

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

docker compose --project-directory "\${PROJECT_DIR}" -f "\${APPS_COMPOSE_FILE}" up -d --build "\${APP_NAME}"
docker compose --project-directory "\${PROJECT_DIR}" -f "\${APPS_COMPOSE_FILE}" ps "\${APP_NAME}"

URL="https://\${APP_NAME}.\${APPS_DOMAIN}"
echo "DEPLOYED_URL=\${URL}"
EOF
}

apps_ensure_layout() {
  apps_run_root install -d -m 0755 -o "${RUNTIME_USER}" -g "${RUNTIME_USER}" "${APPS_ROOT_DIR}"
  apps_run_root install -d -m 0755 "$(dirname "${APPS_REGISTER_SCRIPT}")"
}

apps_sync_mission_control_source_if_enabled() {
  if [[ "${MISSION_CONTROL_ENABLE}" != "true" ]]; then
    log_info "[apps] MISSION_CONTROL_ENABLE=false; skipping Mission Control source sync"
    return 0
  fi

  log_info "[apps] ensuring Mission Control source at ${MISSION_CONTROL_SOURCE_DIR}"
  apps_run_root install -d -m 0755 -o "${RUNTIME_USER}" -g "${RUNTIME_USER}" "$(dirname "${MISSION_CONTROL_SOURCE_DIR}")"

  local quoted_dir quoted_ref quoted_repo
  printf -v quoted_dir '%q' "${MISSION_CONTROL_SOURCE_DIR}"
  printf -v quoted_ref '%q' "${MISSION_CONTROL_SOURCE_REF}"
  printf -v quoted_repo '%q' "${MISSION_CONTROL_SOURCE_REPO}"

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    if [[ -d "${MISSION_CONTROL_SOURCE_DIR}/.git" ]]; then
      apps_run_runtime /bin/bash -lc "git -C ${quoted_dir} fetch --all --tags"
      apps_run_runtime /bin/bash -lc "git -C ${quoted_dir} checkout ${quoted_ref}"
      apps_run_runtime /bin/bash -lc "git -C ${quoted_dir} pull --ff-only origin ${quoted_ref}"
    else
      apps_run_runtime /bin/bash -lc "git clone --branch ${quoted_ref} --depth 1 ${quoted_repo} ${quoted_dir}"
    fi
    return 0
  fi

  command_exists git || die "[apps] git is required for Mission Control source sync"

  if [[ -d "${MISSION_CONTROL_SOURCE_DIR}" && ! -d "${MISSION_CONTROL_SOURCE_DIR}/.git" ]]; then
    die "[apps] Mission Control source path exists but is not a git repository: ${MISSION_CONTROL_SOURCE_DIR}"
  fi

  if [[ -d "${MISSION_CONTROL_SOURCE_DIR}/.git" ]]; then
    apps_run_runtime /bin/bash -lc "git -C ${quoted_dir} fetch --all --tags"
    apps_run_runtime /bin/bash -lc "git -C ${quoted_dir} checkout ${quoted_ref}"
    apps_run_runtime /bin/bash -lc "git -C ${quoted_dir} pull --ff-only origin ${quoted_ref}"
  else
    apps_run_runtime /bin/bash -lc "git clone --branch ${quoted_ref} --depth 1 ${quoted_repo} ${quoted_dir}"
  fi

  [[ -f "${MISSION_CONTROL_FRONTEND_DIR}/package.json" ]] || \
    die "[apps] Mission Control frontend package.json missing: ${MISSION_CONTROL_FRONTEND_DIR}/package.json"
  [[ -f "${MISSION_CONTROL_SOURCE_DIR}/backend/Dockerfile" ]] || \
    die "[apps] Mission Control backend Dockerfile missing: ${MISSION_CONTROL_SOURCE_DIR}/backend/Dockerfile"
}

apps_fix_runtime_permissions() {
  log_info "[apps] ensuring app runtime paths are owned by ${RUNTIME_USER}"
  apps_run_root install -d -m 0755 -o "${RUNTIME_USER}" -g "${RUNTIME_USER}" "${APPS_ROOT_DIR}"
  apps_run_root chown -R "${RUNTIME_USER}:${RUNTIME_USER}" "${APPS_ROOT_DIR}"
  apps_run_root install -d -m 0755 -o "${RUNTIME_USER}" -g "${RUNTIME_USER}" "${APPS_ROOT_DIR}/hub-config"
  apps_run_root chown "${RUNTIME_USER}:${RUNTIME_USER}" "${APPS_COMPOSE_FILE}"
  apps_run_root chmod 0644 "${APPS_COMPOSE_FILE}"
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

  if [[ -f "${APPS_COMPOSE_FILE}" ]]; then
    log_info "[apps] preserving existing compose file at ${APPS_COMPOSE_FILE}"
  else
    apps_write_content_if_changed "${APPS_COMPOSE_FILE}" "0644" "${compose_skeleton}" || true
  fi
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
  apps_sync_mission_control_source_if_enabled
  apps_fix_runtime_permissions
  apps_ensure_hub_during_install
  log_info "[apps] apps registry setup complete"
}
