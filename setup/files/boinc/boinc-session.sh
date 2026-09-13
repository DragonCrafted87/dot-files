#!/usr/bin/env bash
# Switch the live BOINC override between repo active and idle prefs.
#   boinc-session.sh active|idle
# hypridle calls this from idle-display-off/on. Must stay fast and quiet.
# run_gpu_if_user_active in the XML is ignored on Hyprland, so GPU mode
# is set here with --set_gpu_mode.

set -euo pipefail

# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/find-boinccmd.sh"

MODE="${1:-}"
case "$MODE" in
    active | idle) ;;
    *)
        printf 'usage: %s active|idle\n' "${0##*/}" >&2
        exit 2
        ;;
esac

boinc_service_active || exit 0
wait_for_boinc_rpc || exit 0

RPC_AUTH_FILE="${BOINC_DIR}/gui_rpc_auth.cfg"
[[ -f "$RPC_AUTH_FILE" ]] || exit 0
rpc_password="$(tr -d '[:space:]' <"$RPC_AUTH_FILE")"
[[ -n "$rpc_password" ]] || exit 0

# GPU first. Prefs symlink can fail; the card still has to drop when the
# desk wakes.
case "$MODE" in
    active)
        boinc_cmd --passwd "$rpc_password" --set_gpu_mode never
        ;;
    idle)
        boinc_cmd --passwd "$rpc_password" --set_gpu_mode auto
        ;;
esac

src="$(link_boinc_prefs "$MODE")" || exit 0
boinc_cmd --passwd "$rpc_password" --read_global_prefs_override >/dev/null 2>&1 || true
printf 'boinc prefs %s gpu=%s -> %s\n' "$MODE" "$([[ $MODE == idle ]] && echo auto || echo never)" "$src"
