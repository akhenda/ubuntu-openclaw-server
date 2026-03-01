#!/usr/bin/env bash

phase_socket_proxy() {
  if [[ "${SOCKET_PROXY_ENABLE}" != "true" ]]; then
    log_info "[socket-proxy] SOCKET_PROXY_ENABLE=false; skipping docker socket proxy phase"
    return 0
  fi

  log_info "[socket-proxy] socket proxy is enabled; edge phase will deploy docker-socket-proxy"
}
