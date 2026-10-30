#!/bin/sh
set -eu

: "${TAILSCALE_BIN:=tailscale}"
: "${FUNNEL_PATH:=/}"
: "${FUNNEL_RETRY_DELAY:=300}"
: "${BACKEND_WAIT_ATTEMPTS:=90}"
: "${BACKEND_WAIT_DELAY:=2}"

funnel_reset() {
  attempt=1
  while [ "$attempt" -le "${FUNNEL_RESET_RETRIES:-5}" ]; do
    if "$TAILSCALE_BIN" funnel reset >/dev/null 2>&1; then
      echo "funnel state cleared"
      return 0
    fi
    attempt=$((attempt + 1))
    if [ "$attempt" -le "${FUNNEL_RESET_RETRIES:-5}" ]; then
      sleep "${FUNNEL_RESET_DELAY:-10}"
    fi
  done
  echo "WARNING: funnel reset failed ${FUNNEL_RESET_RETRIES:-5} times; a stale rule may still be serving" >&2
  return 0
}

funnel_once() {
  funnel_reset
  if [ "${FUNNEL_ENABLED:-false}" != "true" ]; then
    echo "funnel disabled (FUNNEL_ENABLED=${FUNNEL_ENABLED:-}), staying unpublished"
    return 0
  fi
  if [ -z "${FUNNEL_TARGET:-}" ]; then
    echo "FUNNEL_TARGET is required" >&2
    return 2
  fi
  if "$TAILSCALE_BIN" funnel --bg --set-path "${FUNNEL_PATH}" "${FUNNEL_TARGET}" >/dev/null 2>&1; then
    echo "funnel serving ${FUNNEL_PATH} -> ${FUNNEL_TARGET}"
    return 0
  fi
  return 1
}

ensure_funnel() {
  while ! funnel_once; do
    sleep "$FUNNEL_RETRY_DELAY"
  done
}

wait_for_backend() {
  attempt=1
  while [ "$attempt" -le "$BACKEND_WAIT_ATTEMPTS" ]; do
    if "$TAILSCALE_BIN" status --json 2>/dev/null | grep -q '"BackendState": *"Running"'; then
      return 0
    fi
    attempt=$((attempt + 1))
    if [ "$attempt" -le "$BACKEND_WAIT_ATTEMPTS" ]; then
      sleep "$BACKEND_WAIT_DELAY"
    fi
  done
  return 1
}
