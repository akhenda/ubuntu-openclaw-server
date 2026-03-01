#!/usr/bin/env bash

trim_spaces() {
  local s="$1"
  s="${s#${s%%[![:space:]]*}}"
  s="${s%${s##*[![:space:]]}}"
  printf '%s' "$s"
}

load_config_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    die "Config file not found: $path (copy config/example.env to config/.env and edit values)"
  fi

  log_info "Loading config: $path"

  local line key raw value
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim_spaces "$line")"

    [[ -z "$line" ]] && continue
    [[ "${line:0:1}" == "#" ]] && continue

    if [[ "$line" != *"="* ]]; then
      die "Invalid config line (missing '='): $line"
    fi

    key="${line%%=*}"
    raw="${line#*=}"
    key="$(trim_spaces "$key")"
    value="$(trim_spaces "$raw")"

    [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]] || die "Invalid config key: $key"

    if (( ${#value} >= 2 )) && [[ "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then
      value="${value:1:${#value}-2}"
    elif (( ${#value} >= 2 )) && [[ "${value:0:1}" == "'" && "${value: -1}" == "'" ]]; then
      value="${value:1:${#value}-2}"
    fi

    export "$key=$value"
  done < "$path"
}

set_default_config() {
  : "${ADMIN_USER:=hendaz}"
  : "${RUNTIME_USER:=openclaw}"
  : "${SSH_PORT:=1773}"
  : "${ADMIN_USER_SHELL:=/bin/bash}"
  : "${RUNTIME_USER_SHELL:=/bin/bash}"
  : "${REMOVE_DEFAULT_UBUNTU_USER:=true}"
  : "${FIREWALL_ENABLE:=true}"
  : "${FIREWALL_ALLOW_HTTP:=false}"
  : "${FIREWALL_ALLOW_HTTPS:=false}"
  : "${FIREWALL_EXTRA_TCP_PORTS:=}"
  : "${EDGE_ENABLE:=true}"
  : "${EDGE_ROOT_DIR:=/opt/openclaw}"
  : "${EDGE_START_STACK:=true}"
  : "${EDGE_REQUIRE_TUNNEL_CREDENTIALS:=true}"
  : "${TRAEFIK_IMAGE:=traefik:v3.0}"
  : "${CLOUDFLARED_IMAGE:=cloudflare/cloudflared:latest}"
  : "${TRAEFIK_DASHBOARD_HOST:=traefik.${APPS_DOMAIN}}"
  : "${TRAEFIK_DASHBOARD_USERS:=}"
  : "${CLOUDFLARED_CREDENTIALS_FILE:=}"
  : "${DNS_ENABLE:=true}"
  : "${DNS_ENSURE_WILDCARD_RECORD:=true}"
  : "${DNS_FAIL_ON_ERROR:=true}"
  : "${DNS_BIN_DIR:=${EDGE_ROOT_DIR}/bin}"
  : "${OPENCLAW_ENABLE:=false}"
  : "${OPENCLAW_ROOT_DIR:=${EDGE_ROOT_DIR}/openclaw}"
  : "${OPENCLAW_SOURCE_DIR:=${EDGE_ROOT_DIR}/openclaw-src}"
  : "${OPENCLAW_SOURCE_REPO:=https://github.com/openclaw/openclaw.git}"
  : "${OPENCLAW_SOURCE_REF:=main}"
  : "${OPENCLAW_IMAGE:=openclaw:local}"
  : "${OPENCLAW_BUILD_IMAGE:=true}"
  : "${OPENCLAW_START_STACK:=true}"
  : "${OPENCLAW_MANAGE_SYSTEMD:=true}"
  : "${OPENCLAW_GATEWAY_PORT:=18789}"
  : "${OPENCLAW_CONFIG_FILE:=${OPENCLAW_ROOT_DIR}/config/openclaw.json}"
  : "${OPENCLAW_POLICY_FILE:=${OPENCLAW_ROOT_DIR}/workspace/policies/deploy/AGENTS.md}"
  : "${OPENCLAW_POLICY_INJECTION:=true}"
  : "${OPENCLAW_SYSTEMD_UNIT:=/etc/systemd/system/openclaw-gateway.service}"
  : "${TAILSCALE_ENABLE:=true}"
  : "${TAILSCALE_AUTHKEY:=}"
  : "${TAILSCALE_SSH:=true}"
  : "${TAILSCALE_HOSTNAME:=${BOT_NAME}-${ADMIN_USER}}"
  : "${HUB_ENABLE:=true}"
  : "${HUB_AUTOCREATE_ON_FIRST_APP:=true}"
  : "${HUB_PRIMARY_HOST:=hub.${APPS_DOMAIN}}"
  : "${HUB_ALIAS_HOST:=apps.${DOMAIN}}"
  : "${HUB_STYLE_PROFILE:=modern-minimal}"
  : "${HUB_ICON_STRATEGY:=deterministic-random}"
  : "${APPS_ENABLE:=true}"
  : "${APPS_ROOT_DIR:=${EDGE_ROOT_DIR}/apps}"
  : "${APPS_COMPOSE_FILE:=${APPS_ROOT_DIR}/docker-compose.yml}"
  : "${APPS_VENV_DIR:=${EDGE_ROOT_DIR}/.venv}"
  : "${APPS_REGISTER_SCRIPT:=${DNS_BIN_DIR}/register_app.py}"
  : "${APPS_DEPLOY_SCRIPT:=${DNS_BIN_DIR}/deploy_app.sh}"
  : "${APPS_SETUP_VENV:=true}"
  : "${APPS_VENV_PYTHON:=python3}"
  : "${REPORT_ENABLE:=true}"
  : "${REPORT_SCRIPT:=${DNS_BIN_DIR}/report.sh}"
  : "${REPORT_FAIL_ON_SEND:=false}"
  : "${VERIFY_ENABLE:=true}"
  : "${VERIFY_STRICT:=true}"
  : "${REPORT_OWNER_NAME:=Joseph}"

  : "${EDGE_NETWORK_NAME:=openclaw-edge}"
  : "${EDGE_SUBNET:=172.30.0.0/24}"
  : "${TRAEFIK_IP:=172.30.0.2}"
  : "${CLOUDFLARED_IP:=172.30.0.3}"
  : "${OPENCLAW_GATEWAY_IP:=172.30.0.10}"

  export ADMIN_USER RUNTIME_USER SSH_PORT ADMIN_USER_SHELL RUNTIME_USER_SHELL REMOVE_DEFAULT_UBUNTU_USER
  export FIREWALL_ENABLE FIREWALL_ALLOW_HTTP FIREWALL_ALLOW_HTTPS FIREWALL_EXTRA_TCP_PORTS
  export EDGE_ENABLE EDGE_ROOT_DIR EDGE_START_STACK EDGE_REQUIRE_TUNNEL_CREDENTIALS
  export TRAEFIK_IMAGE CLOUDFLARED_IMAGE TRAEFIK_DASHBOARD_HOST TRAEFIK_DASHBOARD_USERS CLOUDFLARED_CREDENTIALS_FILE
  export DNS_ENABLE DNS_ENSURE_WILDCARD_RECORD DNS_FAIL_ON_ERROR DNS_BIN_DIR
  export OPENCLAW_ENABLE OPENCLAW_ROOT_DIR OPENCLAW_SOURCE_DIR OPENCLAW_SOURCE_REPO OPENCLAW_SOURCE_REF OPENCLAW_IMAGE
  export OPENCLAW_BUILD_IMAGE OPENCLAW_START_STACK OPENCLAW_MANAGE_SYSTEMD OPENCLAW_GATEWAY_PORT
  export OPENCLAW_CONFIG_FILE OPENCLAW_POLICY_FILE OPENCLAW_POLICY_INJECTION OPENCLAW_SYSTEMD_UNIT
  export TAILSCALE_ENABLE TAILSCALE_AUTHKEY TAILSCALE_SSH TAILSCALE_HOSTNAME
  export HUB_ENABLE HUB_AUTOCREATE_ON_FIRST_APP HUB_PRIMARY_HOST HUB_ALIAS_HOST HUB_STYLE_PROFILE HUB_ICON_STRATEGY
  export APPS_ENABLE APPS_ROOT_DIR APPS_COMPOSE_FILE APPS_VENV_DIR APPS_REGISTER_SCRIPT APPS_DEPLOY_SCRIPT
  export APPS_SETUP_VENV APPS_VENV_PYTHON
  export VERIFY_ENABLE VERIFY_STRICT
  export REPORT_ENABLE REPORT_SCRIPT REPORT_FAIL_ON_SEND REPORT_OWNER_NAME
  export EDGE_NETWORK_NAME EDGE_SUBNET TRAEFIK_IP CLOUDFLARED_IP OPENCLAW_GATEWAY_IP
}

validate_required_vars() {
  local -a required=(
    DOMAIN
    APPS_DOMAIN
    BOT_NAME
    TUNNEL_UUID
    CF_ZONE_ID
    CF_API_TOKEN
    TAILSCALE_AUTHKEY
    OPENCLAW_GATEWAY_TOKEN
    OPENCLAW_GATEWAY_PASSWORD
  )

  local name
  for name in "${required[@]}"; do
    [[ -n "${!name:-}" ]] || die "Missing required variable: $name"
  done

  if [[ -z "${ADMIN_SSH_PUBLIC_KEY:-}" && -z "${ADMIN_SSH_PUBLIC_KEY_FILE:-}" ]]; then
    die "Missing admin SSH key. Set ADMIN_SSH_PUBLIC_KEY or ADMIN_SSH_PUBLIC_KEY_FILE."
  fi
}

validate_domain_var() {
  local name="$1"
  local value="${!name:-}"

  [[ "$value" == "${value,,}" ]] || die "$name must be lowercase: $value"
  [[ "$value" =~ ^([a-z0-9-]+\.)+[a-z]{2,}$ ]] || die "$name has invalid domain format: $value"
}

validate_boolean_var() {
  local name="$1"
  local value="${!name:-}"
  [[ "$value" =~ ^(true|false)$ ]] || die "$name must be 'true' or 'false', got: $value"
}

validate_tcp_port() {
  local value="$1"
  [[ "$value" =~ ^[0-9]+$ ]] || return 1
  (( value >= 1 && value <= 65535 )) || return 1
  return 0
}

validate_tcp_port_list_var() {
  local name="$1"
  local raw="${!name:-}"
  [[ -z "${raw}" ]] && return 0

  local normalized="${raw//,/ }"
  local port=""
  for port in ${normalized}; do
    validate_tcp_port "${port}" || die "${name} contains invalid TCP port: ${port}"
  done
}

validate_path_is_absolute() {
  local name="$1"
  local value="${!name:-}"
  [[ "$value" =~ ^/ ]] || die "${name} must be an absolute path, got: ${value}"
}

validate_hostname_like_var() {
  local name="$1"
  local value="${!name:-}"
  [[ -z "${value}" ]] && return 0
  [[ "$value" == "${value,,}" ]] || die "${name} must be lowercase: ${value}"
  [[ "$value" =~ ^([a-z0-9-]+\.)+[a-z]{2,}$ ]] || die "${name} has invalid host format: ${value}"
}

validate_dns_label_var() {
  local name="$1"
  local value="${!name:-}"
  [[ "$value" == "${value,,}" ]] || die "$name must be lowercase: ${value}"
  [[ "$value" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] || die "$name must be a valid DNS label: ${value}"
}

validate_non_empty_trimmed_var() {
  local name="$1"
  local value="${!name:-}"
  local trimmed
  trimmed="$(trim_spaces "${value}")"
  [[ -n "${trimmed}" ]] || die "${name} must not be empty"
}

resolve_admin_ssh_public_key() {
  if [[ -z "${ADMIN_SSH_PUBLIC_KEY:-}" && -n "${ADMIN_SSH_PUBLIC_KEY_FILE:-}" ]]; then
    require_file "${ADMIN_SSH_PUBLIC_KEY_FILE}"
    ADMIN_SSH_PUBLIC_KEY="$(tr -d '\r' < "${ADMIN_SSH_PUBLIC_KEY_FILE}")"
    ADMIN_SSH_PUBLIC_KEY="$(trim_spaces "${ADMIN_SSH_PUBLIC_KEY}")"
    export ADMIN_SSH_PUBLIC_KEY
  fi
}

validate_admin_ssh_public_key() {
  local key="${ADMIN_SSH_PUBLIC_KEY:-}"
  [[ -n "$key" ]] || die "ADMIN_SSH_PUBLIC_KEY resolved to empty value"
  [[ "$key" =~ ^(ssh-(ed25519|rsa)|ecdsa-sha2-nistp[0-9]+)[[:space:]]+[A-Za-z0-9+/=]+([[:space:]].*)?$ ]] || \
    die "ADMIN_SSH_PUBLIC_KEY is not a valid SSH public key format"
}

validate_config() {
  validate_required_vars
  resolve_admin_ssh_public_key

  [[ "$ADMIN_USER" == "hendaz" ]] || die "ADMIN_USER must be 'hendaz' (locked decision), got: $ADMIN_USER"
  [[ "$RUNTIME_USER" == "openclaw" ]] || die "RUNTIME_USER must be 'openclaw' (locked decision), got: $RUNTIME_USER"
  [[ "$SSH_PORT" == "1773" ]] || die "SSH_PORT must be 1773 (locked decision), got: $SSH_PORT"
  validate_tcp_port "${SSH_PORT}" || die "SSH_PORT must be a valid TCP port number"
  [[ "$ADMIN_USER_SHELL" =~ ^/ ]] || die "ADMIN_USER_SHELL must be an absolute shell path"
  [[ "$RUNTIME_USER_SHELL" =~ ^/ ]] || die "RUNTIME_USER_SHELL must be an absolute shell path"
  validate_boolean_var REMOVE_DEFAULT_UBUNTU_USER
  validate_boolean_var FIREWALL_ENABLE
  validate_boolean_var FIREWALL_ALLOW_HTTP
  validate_boolean_var FIREWALL_ALLOW_HTTPS
  validate_tcp_port_list_var FIREWALL_EXTRA_TCP_PORTS
  validate_boolean_var EDGE_ENABLE
  validate_boolean_var EDGE_START_STACK
  validate_boolean_var EDGE_REQUIRE_TUNNEL_CREDENTIALS
  validate_path_is_absolute EDGE_ROOT_DIR
  validate_hostname_like_var TRAEFIK_DASHBOARD_HOST
  validate_boolean_var DNS_ENABLE
  validate_boolean_var DNS_ENSURE_WILDCARD_RECORD
  validate_boolean_var DNS_FAIL_ON_ERROR
  validate_path_is_absolute DNS_BIN_DIR
  validate_boolean_var OPENCLAW_ENABLE
  validate_boolean_var OPENCLAW_BUILD_IMAGE
  validate_boolean_var OPENCLAW_START_STACK
  validate_boolean_var OPENCLAW_MANAGE_SYSTEMD
  validate_boolean_var OPENCLAW_POLICY_INJECTION
  validate_tcp_port "${OPENCLAW_GATEWAY_PORT}" || die "OPENCLAW_GATEWAY_PORT must be a valid TCP port number"
  validate_path_is_absolute OPENCLAW_ROOT_DIR
  validate_path_is_absolute OPENCLAW_SOURCE_DIR
  validate_path_is_absolute OPENCLAW_CONFIG_FILE
  validate_path_is_absolute OPENCLAW_POLICY_FILE
  validate_path_is_absolute OPENCLAW_SYSTEMD_UNIT
  [[ "${OPENCLAW_POLICY_INJECTION}" == "true" ]] || die "OPENCLAW_POLICY_INJECTION must remain true (locked decision)"
  validate_boolean_var TAILSCALE_ENABLE
  validate_boolean_var TAILSCALE_SSH
  validate_dns_label_var TAILSCALE_HOSTNAME
  [[ "${TAILSCALE_ENABLE}" == "true" ]] || die "TAILSCALE_ENABLE must remain true (locked requirement)"
  validate_non_empty_trimmed_var TAILSCALE_AUTHKEY
  (( ${#TAILSCALE_AUTHKEY} >= 20 )) || die "TAILSCALE_AUTHKEY appears too short"
  [[ "${TAILSCALE_AUTHKEY}" == tskey-* ]] || log_warn "TAILSCALE_AUTHKEY does not start with 'tskey-'; verify value is correct."
  validate_boolean_var HUB_ENABLE
  validate_boolean_var HUB_AUTOCREATE_ON_FIRST_APP
  [[ "${HUB_ENABLE}" == "true" ]] || die "HUB_ENABLE must remain true (locked requirement)"
  [[ "${HUB_AUTOCREATE_ON_FIRST_APP}" == "true" ]] || die "HUB_AUTOCREATE_ON_FIRST_APP must remain true (locked requirement)"
  validate_hostname_like_var HUB_PRIMARY_HOST
  if [[ -n "${HUB_ALIAS_HOST:-}" ]]; then
    validate_hostname_like_var HUB_ALIAS_HOST
  fi
  [[ "${HUB_STYLE_PROFILE}" =~ ^(modern-minimal|minimal|creative-minimal)$ ]] || \
    die "HUB_STYLE_PROFILE must be one of: modern-minimal|minimal|creative-minimal"
  [[ "${HUB_ICON_STRATEGY}" =~ ^(deterministic-random|static|emoji-random)$ ]] || \
    die "HUB_ICON_STRATEGY must be one of: deterministic-random|static|emoji-random"
  validate_boolean_var APPS_ENABLE
  validate_boolean_var APPS_SETUP_VENV
  validate_path_is_absolute APPS_ROOT_DIR
  validate_path_is_absolute APPS_COMPOSE_FILE
  validate_path_is_absolute APPS_VENV_DIR
  validate_path_is_absolute APPS_REGISTER_SCRIPT
  validate_path_is_absolute APPS_DEPLOY_SCRIPT
  validate_boolean_var VERIFY_ENABLE
  validate_boolean_var VERIFY_STRICT
  validate_boolean_var REPORT_ENABLE
  validate_path_is_absolute REPORT_SCRIPT
  validate_boolean_var REPORT_FAIL_ON_SEND
  validate_non_empty_trimmed_var REPORT_OWNER_NAME
  if [[ -n "${CLOUDFLARED_CREDENTIALS_FILE:-}" ]]; then
    validate_path_is_absolute CLOUDFLARED_CREDENTIALS_FILE
  fi

  [[ "$EDGE_NETWORK_NAME" == "openclaw-edge" ]] || die "EDGE_NETWORK_NAME must be openclaw-edge, got: $EDGE_NETWORK_NAME"

  validate_domain_var DOMAIN
  validate_domain_var APPS_DOMAIN
  validate_admin_ssh_public_key

  [[ "$BOT_NAME" == "${BOT_NAME,,}" ]] || die "BOT_NAME must be lowercase: $BOT_NAME"
  [[ "$BOT_NAME" =~ ^[a-z0-9-]+$ ]] || die "BOT_NAME has invalid format: $BOT_NAME"
  [[ "$BOT_NAME" != "traefik" ]] || die "BOT_NAME cannot be reserved name 'traefik'"

  [[ "$TUNNEL_UUID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || \
    die "TUNNEL_UUID must be UUID format"

  [[ "$CF_ZONE_ID" =~ ^[0-9a-fA-F]{32}$ ]] || die "CF_ZONE_ID must be 32 hex chars"
  (( ${#CF_API_TOKEN} >= 20 )) || die "CF_API_TOKEN appears too short"

  validate_ipv4 "$TRAEFIK_IP" || die "Invalid TRAEFIK_IP: $TRAEFIK_IP"
  validate_ipv4 "$CLOUDFLARED_IP" || die "Invalid CLOUDFLARED_IP: $CLOUDFLARED_IP"
  validate_ipv4 "$OPENCLAW_GATEWAY_IP" || die "Invalid OPENCLAW_GATEWAY_IP: $OPENCLAW_GATEWAY_IP"

  if [[ "$TRAEFIK_IP" == "$CLOUDFLARED_IP" || "$TRAEFIK_IP" == "$OPENCLAW_GATEWAY_IP" || "$CLOUDFLARED_IP" == "$OPENCLAW_GATEWAY_IP" ]]; then
    die "TRAEFIK_IP, CLOUDFLARED_IP, and OPENCLAW_GATEWAY_IP must be unique"
  fi

  if [[ "$APPS_DOMAIN" == "$DOMAIN" ]]; then
    log_info "Domain layout: Option A (recommended)"
  elif [[ "$APPS_DOMAIN" == "apps.$DOMAIN" ]]; then
    log_warn "Domain layout: Option B selected. Ensure Cloudflare SSL coverage is explicitly handled."
  else
    log_warn "Custom APPS_DOMAIN layout detected: $APPS_DOMAIN (ensure wildcard cert and DNS strategy are valid)."
  fi

  if [[ "${EDGE_ROOT_DIR}" != "/opt/openclaw" ]]; then
    log_warn "EDGE_ROOT_DIR is non-default (${EDGE_ROOT_DIR}). Canonical production contract expects /opt/openclaw."
  fi

  if [[ -n "${REPORT_CHANNEL:-}" && -z "${REPORT_TARGET:-}" ]]; then
    log_warn "REPORT_CHANNEL is set but REPORT_TARGET is empty; report delivery will fallback to stdout."
  fi

  log_info "Configuration validation passed"
}

print_config_summary() {
  cat <<SUMMARY
Configuration summary:
  DOMAIN=${DOMAIN}
  APPS_DOMAIN=${APPS_DOMAIN}
  BOT_NAME=${BOT_NAME}
  TUNNEL_UUID=${TUNNEL_UUID}
  CF_ZONE_ID=${CF_ZONE_ID}
  CF_API_TOKEN=$(redact_secret "${CF_API_TOKEN}")
  ADMIN_USER=${ADMIN_USER}
  RUNTIME_USER=${RUNTIME_USER}
  SSH_PORT=${SSH_PORT}
  EDGE_NETWORK_NAME=${EDGE_NETWORK_NAME}
  EDGE_SUBNET=${EDGE_SUBNET}
  TRAEFIK_IP=${TRAEFIK_IP}
  CLOUDFLARED_IP=${CLOUDFLARED_IP}
  OPENCLAW_GATEWAY_IP=${OPENCLAW_GATEWAY_IP}
  OPENCLAW_GATEWAY_TOKEN=$(redact_secret "${OPENCLAW_GATEWAY_TOKEN}")
  OPENCLAW_GATEWAY_PASSWORD=$(redact_secret "${OPENCLAW_GATEWAY_PASSWORD}")
  ADMIN_SSH_PUBLIC_KEY=${ADMIN_SSH_PUBLIC_KEY%% *} ****
  ADMIN_SSH_PUBLIC_KEY_FILE=${ADMIN_SSH_PUBLIC_KEY_FILE:-<unset>}
  ADMIN_USER_SHELL=${ADMIN_USER_SHELL}
  RUNTIME_USER_SHELL=${RUNTIME_USER_SHELL}
  REMOVE_DEFAULT_UBUNTU_USER=${REMOVE_DEFAULT_UBUNTU_USER}
  FIREWALL_ENABLE=${FIREWALL_ENABLE}
  FIREWALL_ALLOW_HTTP=${FIREWALL_ALLOW_HTTP}
  FIREWALL_ALLOW_HTTPS=${FIREWALL_ALLOW_HTTPS}
  FIREWALL_EXTRA_TCP_PORTS=${FIREWALL_EXTRA_TCP_PORTS:-<unset>}
  EDGE_ENABLE=${EDGE_ENABLE}
  EDGE_ROOT_DIR=${EDGE_ROOT_DIR}
  EDGE_START_STACK=${EDGE_START_STACK}
  EDGE_REQUIRE_TUNNEL_CREDENTIALS=${EDGE_REQUIRE_TUNNEL_CREDENTIALS}
  TRAEFIK_IMAGE=${TRAEFIK_IMAGE}
  CLOUDFLARED_IMAGE=${CLOUDFLARED_IMAGE}
  TRAEFIK_DASHBOARD_HOST=${TRAEFIK_DASHBOARD_HOST}
  TRAEFIK_DASHBOARD_USERS=$(redact_secret "${TRAEFIK_DASHBOARD_USERS}")
  CLOUDFLARED_CREDENTIALS_FILE=${CLOUDFLARED_CREDENTIALS_FILE:-<unset>}
  DNS_ENABLE=${DNS_ENABLE}
  DNS_ENSURE_WILDCARD_RECORD=${DNS_ENSURE_WILDCARD_RECORD}
  DNS_FAIL_ON_ERROR=${DNS_FAIL_ON_ERROR}
  DNS_BIN_DIR=${DNS_BIN_DIR}
  OPENCLAW_ENABLE=${OPENCLAW_ENABLE}
  OPENCLAW_ROOT_DIR=${OPENCLAW_ROOT_DIR}
  OPENCLAW_SOURCE_DIR=${OPENCLAW_SOURCE_DIR}
  OPENCLAW_SOURCE_REPO=${OPENCLAW_SOURCE_REPO}
  OPENCLAW_SOURCE_REF=${OPENCLAW_SOURCE_REF}
  OPENCLAW_IMAGE=${OPENCLAW_IMAGE}
  OPENCLAW_BUILD_IMAGE=${OPENCLAW_BUILD_IMAGE}
  OPENCLAW_START_STACK=${OPENCLAW_START_STACK}
  OPENCLAW_MANAGE_SYSTEMD=${OPENCLAW_MANAGE_SYSTEMD}
  OPENCLAW_GATEWAY_PORT=${OPENCLAW_GATEWAY_PORT}
  OPENCLAW_CONFIG_FILE=${OPENCLAW_CONFIG_FILE}
  OPENCLAW_POLICY_FILE=${OPENCLAW_POLICY_FILE}
  OPENCLAW_POLICY_INJECTION=${OPENCLAW_POLICY_INJECTION}
  OPENCLAW_SYSTEMD_UNIT=${OPENCLAW_SYSTEMD_UNIT}
  TAILSCALE_ENABLE=${TAILSCALE_ENABLE}
  TAILSCALE_AUTHKEY=$(redact_secret "${TAILSCALE_AUTHKEY}")
  TAILSCALE_SSH=${TAILSCALE_SSH}
  TAILSCALE_HOSTNAME=${TAILSCALE_HOSTNAME}
  HUB_ENABLE=${HUB_ENABLE}
  HUB_AUTOCREATE_ON_FIRST_APP=${HUB_AUTOCREATE_ON_FIRST_APP}
  HUB_PRIMARY_HOST=${HUB_PRIMARY_HOST}
  HUB_ALIAS_HOST=${HUB_ALIAS_HOST:-<unset>}
  HUB_STYLE_PROFILE=${HUB_STYLE_PROFILE}
  HUB_ICON_STRATEGY=${HUB_ICON_STRATEGY}
  APPS_ENABLE=${APPS_ENABLE}
  APPS_ROOT_DIR=${APPS_ROOT_DIR}
  APPS_COMPOSE_FILE=${APPS_COMPOSE_FILE}
  APPS_VENV_DIR=${APPS_VENV_DIR}
  APPS_REGISTER_SCRIPT=${APPS_REGISTER_SCRIPT}
  APPS_DEPLOY_SCRIPT=${APPS_DEPLOY_SCRIPT}
  APPS_SETUP_VENV=${APPS_SETUP_VENV}
  APPS_VENV_PYTHON=${APPS_VENV_PYTHON}
  VERIFY_ENABLE=${VERIFY_ENABLE}
  VERIFY_STRICT=${VERIFY_STRICT}
  REPORT_ENABLE=${REPORT_ENABLE}
  REPORT_SCRIPT=${REPORT_SCRIPT}
  REPORT_FAIL_ON_SEND=${REPORT_FAIL_ON_SEND}
  REPORT_OWNER_NAME=${REPORT_OWNER_NAME}
  REPORT_CHANNEL=${REPORT_CHANNEL:-<unset>}
  REPORT_TARGET=${REPORT_TARGET:-<unset>}
SUMMARY
}
