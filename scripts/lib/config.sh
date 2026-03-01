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

    if [[ "$value" =~ ^".*"$ ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "$value" =~ ^\'.*\'$ ]]; then
      value="${value:1:${#value}-2}"
    fi

    export "$key=$value"
  done < "$path"
}

set_default_config() {
  : "${ADMIN_USER:=hendaz}"
  : "${RUNTIME_USER:=openclaw}"
  : "${SSH_PORT:=1773}"

  : "${EDGE_NETWORK_NAME:=openclaw-edge}"
  : "${EDGE_SUBNET:=172.30.0.0/24}"
  : "${TRAEFIK_IP:=172.30.0.2}"
  : "${CLOUDFLARED_IP:=172.30.0.3}"
  : "${OPENCLAW_GATEWAY_IP:=172.30.0.10}"

  export ADMIN_USER RUNTIME_USER SSH_PORT
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
    OPENCLAW_GATEWAY_TOKEN
    OPENCLAW_GATEWAY_PASSWORD
  )

  local name
  for name in "${required[@]}"; do
    [[ -n "${!name:-}" ]] || die "Missing required variable: $name"
  done
}

validate_domain_var() {
  local name="$1"
  local value="${!name:-}"

  [[ "$value" == "${value,,}" ]] || die "$name must be lowercase: $value"
  [[ "$value" =~ ^([a-z0-9-]+\.)+[a-z]{2,}$ ]] || die "$name has invalid domain format: $value"
}

validate_config() {
  validate_required_vars

  [[ "$ADMIN_USER" == "hendaz" ]] || die "ADMIN_USER must be 'hendaz' (locked decision), got: $ADMIN_USER"
  [[ "$RUNTIME_USER" == "openclaw" ]] || die "RUNTIME_USER must be 'openclaw' (locked decision), got: $RUNTIME_USER"
  [[ "$SSH_PORT" == "1773" ]] || die "SSH_PORT must be 1773 (locked decision), got: $SSH_PORT"

  [[ "$EDGE_NETWORK_NAME" == "openclaw-edge" ]] || die "EDGE_NETWORK_NAME must be openclaw-edge, got: $EDGE_NETWORK_NAME"

  validate_domain_var DOMAIN
  validate_domain_var APPS_DOMAIN

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
  REPORT_CHANNEL=${REPORT_CHANNEL:-<unset>}
  REPORT_TARGET=${REPORT_TARGET:-<unset>}
SUMMARY
}
