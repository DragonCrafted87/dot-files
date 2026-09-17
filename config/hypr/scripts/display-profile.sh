#!/usr/bin/env bash
# Apply Hyprland monitor layouts from conf.d/monitors.d/*.conf.
# Profile state and audio live in display-switch.sh / display-audio.sh.
set -euo pipefail

HOST="$(hostname -s 2>/dev/null || hostname)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITORS_D="${SCRIPT_DIR}/../conf.d/monitors.d"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
PROFILE_FILE="${STATE_DIR}/display-profile"
SAVED_WS_FILE="${STATE_DIR}/saved-monitor-workspaces"
RESTORE_WS_PID_FILE="${STATE_DIR}/restore-ws.pid"
APPLY_LOCK_FILE="${STATE_DIR}/apply.lock"
RUNEWYRM_IDLE_MONITOR="HDMI-A-1"
RUNEWYRM_DP_MONITORS=(DP-2 DP-3)
QUIET=0
LOCK_HELD=0

notify() {
    local msg="$1"
    printf '%s\n' "$msg"
    [[ "$QUIET" -eq 1 ]] && return 0
    if command -v hyprctl >/dev/null 2>&1; then
        hyprctl notify -1 2500 "rgb(305cde)" "$msg" >/dev/null 2>&1 || true
    fi
}

need_hypr() {
    command -v hyprctl >/dev/null 2>&1 || { echo "hyprctl not found" >&2; return 1; }
}

# hyprctl keyword monitor wants 2560x1440@143.91, not @143.91Hz.
normalize_monitor_spec() {
    printf '%s\n' "$1" | sed 's/@\([0-9.][0-9.]*\)Hz,/@\1,/'
}

keyword_monitor() {
    local spec
    spec="$(normalize_monitor_spec "$1")"
    hyprctl keyword monitor "$spec" >/dev/null 2>&1 || true
}

dpms() {
    local action="$1"
    local mon="${2:-}"
    if [[ -n "$mon" ]]; then
        hyprctl dispatch dpms "$action" "$mon" >/dev/null 2>&1 || true
    else
        hyprctl dispatch dpms "$action" >/dev/null 2>&1 || true
    fi
}

acquire_apply_lock() {
    mkdir -p "$STATE_DIR"
    exec 9>"$APPLY_LOCK_FILE"
    if ! flock -w 25 9; then
        echo "display-profile: timed out waiting for apply.lock" >&2
        exec 9>&-
        return 1
    fi
    LOCK_HELD=1
    return 0
}

release_apply_lock() {
    [[ "$LOCK_HELD" -eq 1 ]] || return 0
    flock -u 9 2>/dev/null || true
    exec 9>&-
    LOCK_HELD=0
}

with_apply_lock() {
    acquire_apply_lock || return 1
    return 0
}

trap release_apply_lock EXIT

current_profile() {
    if [[ -f "$PROFILE_FILE" ]]; then tr -d '[:space:]' <"$PROFILE_FILE"; else echo ""; fi
}
