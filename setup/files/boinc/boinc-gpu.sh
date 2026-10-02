#!/usr/bin/env bash
# Turn BOINC GPU work on or off.
#   boinc-gpu idle     display blanked -> GPU mode always
#   boinc-gpu active   display awake   -> GPU mode never
# Wayland does not update BOINC's own idle timer, and desktop prefs leave
# the GPU off while the client thinks someone is at the machine. The
# display scripts call this so blanking is the switch.
# Installed on PATH as /usr/local/bin/boinc-gpu.

set -euo pipefail

OWNER="${SUDO_USER:-${DOTFILES_USER:-dragon}}"
BOINC_DIR="${BOINC_DIR:-/home/${OWNER}/.local/share/boinc}"
BOINC_HOST="${BOINC_HOST:-127.0.0.1}"
BOINC_PORT="${BOINC_PORT:-31416}"
BOINCCMD="${BOINCCMD:-/usr/local/bin/boinccmd}"

usage() {
    printf 'usage: %s active|idle\n' "${0##*/}" >&2
}

# Idle hooks must not stall the display. A terminal run reports the miss.
quiet_fail() {
    if [[ -t 1 ]]; then
        printf 'boinc-gpu: %s\n' "$*" >&2
        exit 1
    fi
    exit 0
}

MODE="${1:-}"
case "$MODE" in
    active) gpu_mode="never" ;;
    idle) gpu_mode="always" ;;
    *)
        usage
        exit 2
        ;;
esac

if [[ ! -x "$BOINCCMD" ]]; then
    quiet_fail "${BOINCCMD} is missing"
fi

if ! systemctl --user is-active --quiet boinc-client.service 2>/dev/null \
    && ! systemctl is-active --quiet boinc-client.service 2>/dev/null; then
    quiet_fail "boinc-client is not running"
fi

rpc_file="${BOINC_DIR}/gui_rpc_auth.cfg"
if [[ ! -f "$rpc_file" ]]; then
    quiet_fail "missing ${rpc_file}"
fi
rpc_password="$(tr -d '[:space:]' <"$rpc_file")"
if [[ -z "$rpc_password" ]]; then
    quiet_fail "empty RPC password"
fi

if ! timeout 1 bash -c "echo >/dev/tcp/${BOINC_HOST}/${BOINC_PORT}" 2>/dev/null; then
    quiet_fail "GUI RPC is not listening on ${BOINC_HOST}:${BOINC_PORT}"
fi

timeout 8 "$BOINCCMD" --host "$BOINC_HOST" --passwd "$rpc_password" \
    --set_gpu_mode "$gpu_mode" >/dev/null
