#!/usr/bin/env bash

dns_run_root() {
  if (( EUID == 0 )); then
    run_cmd "$@"
    return $?
  fi

  command_exists sudo || die "[dns] sudo is required when not running as root"
  run_cmd sudo "$@"
}

dns_write_content_if_changed() {
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
    log_info "[dns] no changes for ${target}"
    rm -f "${tmp_file}"
    return 1
  fi

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[dns] [dry-run] would update ${target}"
    rm -f "${tmp_file}"
    return 0
  fi

  dns_run_root install -d -m 0755 "$(dirname "${target}")"
  dns_run_root cp "${tmp_file}" "${target}"
  dns_run_root chown root:root "${target}"
  dns_run_root chmod "${mode}" "${target}"
  rm -f "${tmp_file}"
  return 0
}

dns_ensure_script_path() {
  printf '%s/cf_dns_ensure_wildcard.sh' "${DNS_BIN_DIR}"
}

dns_upsert_script_path() {
  printf '%s/cf_dns_upsert_subdomain.sh' "${DNS_BIN_DIR}"
}

dns_render_ensure_wildcard_script() {
  cat <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${CF_ZONE_ID:?}"
: "${CF_API_TOKEN:?}"
: "${APPS_DOMAIN:?}"
: "${TUNNEL_UUID:?}"

NAME="*.${APPS_DOMAIN}"
TARGET="${TUNNEL_UUID}.cfargotunnel.com"

auth=(-H "Authorization: Bearer ${CF_API_TOKEN}" -H "Content-Type: application/json")

existing_id="$(
  curl -sS "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?type=CNAME&name=${NAME}" \
    "${auth[@]}" | jq -r '.result[0].id // empty'
)"

if [[ -n "${existing_id}" ]]; then
  echo "OK: wildcard exists: ${NAME}"
  exit 0
fi

echo "Creating wildcard CNAME: ${NAME} -> ${TARGET}"
curl -sS -X POST "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records" \
  "${auth[@]}" \
  --data "$(jq -n --arg type "CNAME" --arg name "${NAME}" --arg content "${TARGET}" \
    '{type:$type,name:$name,content:$content,ttl:1,proxied:true}')" \
  | jq -e '.success == true' >/dev/null

echo "OK: created wildcard CNAME"
EOF
}

dns_render_upsert_subdomain_script() {
  cat <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${CF_ZONE_ID:?}"
: "${CF_API_TOKEN:?}"
: "${HOSTNAME:?}"
: "${TUNNEL_UUID:?}"

TARGET="${TUNNEL_UUID}.cfargotunnel.com"
auth=(-H "Authorization: Bearer ${CF_API_TOKEN}" -H "Content-Type: application/json")

existing="$(
  curl -sS "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?type=CNAME&name=${HOSTNAME}" \
    "${auth[@]}" | jq -r '.result[0].id // empty'
)"

payload="$(jq -n --arg type "CNAME" --arg name "${HOSTNAME}" --arg content "${TARGET}" \
  '{type:$type,name:$name,content:$content,ttl:1,proxied:true}')"

if [[ -n "${existing}" ]]; then
  echo "Updating CNAME: ${HOSTNAME} -> ${TARGET}"
  curl -sS -X PUT "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${existing}" \
    "${auth[@]}" --data "${payload}" | jq -e '.success == true' >/dev/null
else
  echo "Creating CNAME: ${HOSTNAME} -> ${TARGET}"
  curl -sS -X POST "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records" \
    "${auth[@]}" --data "${payload}" | jq -e '.success == true' >/dev/null
fi

echo "OK: DNS ensured for ${HOSTNAME}"
EOF
}

dns_require_prereqs() {
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    return 0
  fi

  command_exists curl || die "[dns] curl is required"
  command_exists jq || die "[dns] jq is required"
}

dns_write_helper_scripts() {
  local ensure_script
  local upsert_script
  ensure_script="$(dns_ensure_script_path)"
  upsert_script="$(dns_upsert_script_path)"

  local ensure_content
  local upsert_content
  ensure_content="$(dns_render_ensure_wildcard_script)"
  upsert_content="$(dns_render_upsert_subdomain_script)"

  dns_write_content_if_changed "${ensure_script}" "0755" "${ensure_content}" || true
  dns_write_content_if_changed "${upsert_script}" "0755" "${upsert_content}" || true
}

dns_run_wildcard_ensure() {
  local ensure_script
  ensure_script="$(dns_ensure_script_path)"

  if ! run_cmd "${ensure_script}"; then
    if [[ "${DNS_FAIL_ON_ERROR}" == "true" ]]; then
      die "[dns] wildcard DNS ensure failed"
    fi
    log_warn "[dns] wildcard DNS ensure failed; continuing because DNS_FAIL_ON_ERROR=false"
  fi
}

phase_dns() {
  if [[ "${DNS_ENABLE}" != "true" ]]; then
    log_info "[dns] DNS_ENABLE=false; skipping Cloudflare DNS helper setup"
    return 0
  fi

  log_info "[dns] configuring Cloudflare DNS helper scripts"
  dns_require_prereqs
  dns_run_root install -d -m 0755 "${DNS_BIN_DIR}"
  dns_write_helper_scripts

  if [[ "${DNS_ENSURE_WILDCARD_RECORD}" == "true" ]]; then
    log_info "[dns] ensuring wildcard DNS record via helper script"
    dns_run_wildcard_ensure
  else
    log_info "[dns] DNS_ENSURE_WILDCARD_RECORD=false; helper scripts generated only"
  fi

  log_info "[dns] DNS helper setup complete"
}
