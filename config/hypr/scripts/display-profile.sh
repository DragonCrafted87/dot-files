#!/usr/bin/env bash
# Apply or switch Hyprland display profiles by hostname.
set -euo pipefail

HOST="$(hostname -s 2>/dev/null || hostname)"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
PROFILE_FILE="${STATE_DIR}/display-profile"
SAVED_SINK_FILE="${STATE_DIR}/desk-audio-sink"
SAVED_WS_FILE="${STATE_DIR}/saved-monitor-workspaces"
RESTORE_WS_PID_FILE="${STATE_DIR}/restore-ws.pid"
RUNEWYRM_IDLE_MONITOR="HDMI-A-1"
THEATER_SINK_MATCH="${THEATER_SINK_MATCH:-hdmi}"
DESK_SINK_MATCH="${DESK_SINK_MATCH:-}"
QUIET=0

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

keyword_monitor() { hyprctl keyword monitor "$1" >/dev/null; }

save_profile() {
    mkdir -p "$STATE_DIR"
    printf '%s\n' "$1" >"$PROFILE_FILE"
}

current_profile() {
    if [[ -f "$PROFILE_FILE" ]]; then tr -d '[:space:]' <"$PROFILE_FILE"; else echo ""; fi
}

list_sinks() { command -v pactl >/dev/null 2>&1 && pactl list short sinks 2>/dev/null | awk '{print $2}'; }

default_sink() { command -v pactl >/dev/null 2>&1 && pactl get-default-sink 2>/dev/null || true; }

find_sink() {
    local match="$1"
    [[ -n "$match" ]] || return 1
    list_sinks | awk -v m="$match" 'BEGIN{IGNORECASE=1} $0 ~ m {print; exit}'
}

move_all_streams() {
    local sink="$1"
    command -v pactl >/dev/null 2>&1 || return 0
    pactl list short sink-inputs 2>/dev/null | awk '{print $1}' | while read -r id; do
        [[ -n "$id" ]] || continue
        pactl move-sink-input "$id" "$sink" >/dev/null 2>&1 || true
    done
}

set_sink() {
    local sink="$1"
    [[ -n "$sink" ]] || return 1
    pactl set-default-sink "$sink"
    move_all_streams "$sink"
    notify "Audio → ${sink}"
}

save_current_sink() {
    local sink
    sink="$(default_sink)"
    [[ -n "$sink" ]] || return 0
    if [[ -n "$THEATER_SINK_MATCH" ]] && grep -Fiq "$THEATER_SINK_MATCH" <<<"$sink"; then
        return 0
    fi
    mkdir -p "$STATE_DIR"
    printf '%s\n' "$sink" >"$SAVED_SINK_FILE"
}

restore_desk_audio() {
    command -v pactl >/dev/null 2>&1 || return 0
    local sink=""
    if [[ -n "$DESK_SINK_MATCH" ]]; then
        sink="$(find_sink "$DESK_SINK_MATCH" || true)"
    fi
    if [[ -z "$sink" && -f "$SAVED_SINK_FILE" ]]; then
        sink="$(tr -d '[:space:]' <"$SAVED_SINK_FILE")"
        list_sinks | grep -Fxq "$sink" || sink=""
    fi
    [[ -n "$sink" ]] && set_sink "$sink" || true
}

apply_theater_audio() {
    command -v pactl >/dev/null 2>&1 || { notify "pactl not found; skipped theater audio"; return 0; }
    local current sink
    current="$(default_sink)"
    if [[ -n "$current" && -n "$THEATER_SINK_MATCH" ]] && grep -Fiq "$THEATER_SINK_MATCH" <<<"$current"; then
        return 0
    fi
    save_current_sink
    sink="$(find_sink "$THEATER_SINK_MATCH" || true)"
    if [[ -z "$sink" ]]; then
        notify "No sink matched '${THEATER_SINK_MATCH}'. Run: pactl list short sinks"
        return 0
    fi
    set_sink "$sink" || true
}

apply_desk_monitors() {
    keyword_monitor "DP-2,2560x1440@143.91,0x0,1"
    keyword_monitor "DP-3,3440x1440@144,2560x0,1"
    keyword_monitor "HDMI-A-1,2560x1440@143.91Hz,6000x0,1"
}

apply_theater_monitors() {
    keyword_monitor "DP-2,2560x1440@143.91,0x0,1"
    keyword_monitor "DP-3,3440x1440@144,2560x0,1"
    keyword_monitor "HDMI-A-1,preferred,auto,1"
}

apply_workshare_monitors() {
    keyword_monitor "DP-2,disable"
    keyword_monitor "DP-3,disable"
    keyword_monitor "HDMI-A-1,2560x1440@143.91Hz,0x0,1"
}

apply_default_monitors() { keyword_monitor ",preferred,highrr,auto"; }

apply_runewyrm() {
    local profile="${1:-desk}"
    case "$profile" in
        desk) apply_desk_monitors; restore_desk_audio ;;
        theater) apply_theater_monitors; apply_theater_audio ;;
        workshare) apply_workshare_monitors; restore_desk_audio ;;
        *) echo "unknown runewyrm profile: $profile" >&2; return 1 ;;
    esac
    save_profile "$profile"
    notify "Display profile: ${HOST}/${profile}"
}

apply_other_host() {
    apply_default_monitors
    save_profile "default"
}

workspaces_on_monitor() {
    local mon="$1"
    hyprctl workspaces -j 2>/dev/null | python3 -c '
import json, sys
mon = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)
for w in data:
    if w.get("monitor") != mon:
        continue
    name = str(w.get("name") or "")
    wid = w.get("id")
    if name.startswith("special"):
        print(name)
    elif wid is not None:
        print(wid)
' "$mon" 2>/dev/null || true
}

save_monitor_workspaces() {
    local mon="$1"
    mkdir -p "$STATE_DIR"
    {
        printf 'monitor=%s\n' "$mon"
        workspaces_on_monitor "$mon" | awk '{print "workspace=" $0}'
    } >"$SAVED_WS_FILE"
}

monitor_is_live() {
    local mon="$1"
    hyprctl monitors -j 2>/dev/null | python3 -c '
import json, sys
mon = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(1)
for m in data:
    if m.get("name") != mon:
        continue
    raise SystemExit(1 if m.get("disabled") is True else 0)
raise SystemExit(1)
' "$mon" 2>/dev/null
}

wait_for_unlock() {
    local waited=0
    while command -v pidof >/dev/null 2>&1 && pidof hyprlock >/dev/null 2>&1; do
        sleep 0.4
        waited=1
    done
    [[ "$waited" -eq 1 ]] && sleep 0.3
}

wait_for_monitor() {
    local mon="$1" i
    for i in 1 2 3 4 5 6 7 8 9 10; do
        monitor_is_live "$mon" && return 0
        sleep 0.25
    done
    return 1
}

restore_saved_workspaces_now() {
    [[ -f "$SAVED_WS_FILE" ]] || return 0
    local mon ws
    mon="$(awk -F= '/^monitor=/{print $2; exit}' "$SAVED_WS_FILE")"
    [[ -n "$mon" ]] || return 0
    wait_for_monitor "$mon" || return 0
    while IFS= read -r ws; do
        [[ -n "$ws" ]] || continue
        hyprctl dispatch moveworkspacetomonitor "$ws" "$mon" >/dev/null 2>&1 || true
    done < <(awk -F= '/^workspace=/{print $2}' "$SAVED_WS_FILE")
    rm -f "$SAVED_WS_FILE"
}

schedule_workspace_restore() {
    [[ -f "$SAVED_WS_FILE" ]] || return 0
    if [[ -f "$RESTORE_WS_PID_FILE" ]]; then
        local old
        old="$(tr -d '[:space:]' <"$RESTORE_WS_PID_FILE")"
        if [[ -n "$old" ]] && kill -0 "$old" 2>/dev/null; then
            return 0
        fi
    fi
    if command -v pidof >/dev/null 2>&1 && pidof hyprlock >/dev/null 2>&1; then
        (
            wait_for_unlock
            restore_saved_workspaces_now
            rm -f "$RESTORE_WS_PID_FILE"
        ) &
        mkdir -p "$STATE_DIR"
        echo $! >"$RESTORE_WS_PID_FILE"
    else
        restore_saved_workspaces_now
    fi
}

cmd_restore_ws() { need_hypr; QUIET=1; schedule_workspace_restore; }

cmd_apply() {
    need_hypr
    QUIET=1
    if [[ "$HOST" == "runewyrm" ]]; then
        local profile
        profile="$(current_profile)"
        [[ -n "$profile" && "$profile" != "default" ]] || profile="desk"
        apply_runewyrm "$profile"
    else
        apply_other_host
    fi
    schedule_workspace_restore
}

cmd_set() {
    local profile="$1"
    need_hypr
    if [[ "$HOST" != "runewyrm" ]]; then
        notify "Profiles desk/theater/workshare are runewyrm-only (this host is ${HOST})"
        apply_other_host
        return 0
    fi
    apply_runewyrm "$profile"
    schedule_workspace_restore
}

idle_off_runewyrm() {
    save_monitor_workspaces "$RUNEWYRM_IDLE_MONITOR"
    hyprctl dispatch dpms off
    sleep 0.3
    keyword_monitor "${RUNEWYRM_IDLE_MONITOR},disable"
}

idle_off_other() { hyprctl dispatch dpms off; }

cmd_idle_off() {
    need_hypr
    QUIET=1
    case "$HOST" in
        runewyrm) idle_off_runewyrm ;;
        *) idle_off_other ;;
    esac
}

cmd_status() {
    printf 'host:            %s\n' "$HOST"
    printf 'saved profile:   %s\n' "$(current_profile)"
    printf 'default sink:    %s\n' "$(default_sink)"
    if [[ -f "$SAVED_WS_FILE" ]]; then
        printf 'pending ws:\n'
        sed 's/^/  /' "$SAVED_WS_FILE"
    fi
}

cmd_list() {
    if [[ "$HOST" == "runewyrm" ]]; then
        printf '%s\n' "runewyrm profiles: desk, theater, workshare"
    else
        printf '%s\n' "${HOST}: default preferred/auto layout"
    fi
}

usage() { echo "Usage: display-profile.sh [apply|idle-off|restore-ws|status|list|desk|theater|workshare]"; }

main() {
    local cmd="${1:-apply}"
    case "$cmd" in
        apply|"") cmd_apply ;;
        idle-off) cmd_idle_off ;;
        restore-ws) cmd_restore_ws ;;
        status) cmd_status ;;
        list) cmd_list ;;
        desk|theater|workshare) cmd_set "$cmd" ;;
        -h|--help|help) usage ;;
        *) usage >&2; exit 1 ;;
    esac
}

main "$@"
