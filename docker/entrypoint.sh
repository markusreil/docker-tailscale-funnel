#!/bin/sh
set -eu
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
. "$SCRIPT_DIR/funnel.sh"
: "${CONTAINERBOOT_BIN:=/usr/local/bin/containerboot}"

"$CONTAINERBOOT_BIN" &
boot_pid=$!
trap 'kill -TERM "$boot_pid" 2>/dev/null; wait "$boot_pid"' TERM INT

wait_for_backend || echo "WARNING: backend not Running after $BACKEND_WAIT_ATTEMPTS attempts; continuing anyway" >&2

ensure_funnel &

wait "$boot_pid"
