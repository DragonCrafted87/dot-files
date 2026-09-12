#!/usr/bin/env bash
# Apply or switch Hyprland display profiles by hostname.
# Monitor layouts come only from conf.d/monitors.d/*.conf.
set -euo pipefail

HOST="$(hostname -s 2>/dev/null || hostname)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITORS_D="${SCRIPT_DIR}/../conf.d/monitors.d"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
PROFILE_FILE="${STATE_DIR}/display-profile"
SAVED_SINK_FILE="${STATE_DIR}/desk-audio-sink"
SAVED_WS_FILE="${STATE_DIR}/saved-monitor-workspaces"
RESTORE_WS_PID_FILE="${STATE_DIR}/restore-ws.pid"
APPLY_LOCK_FILE="${STATE_DIR}/apply.lock"
RUNEWYRM_IDLE_MONITOR="HDMI-A-1"
RUNEWYRM_DP_MONITORS=(DP-2 DP-3)
THEATER_SINK_MATCH="${THEATER_SINK_MATCH:-hdmi}"
DESK_SINK_MATCH="${DESK_SINK_MATCH:-}"
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

keyword_monitor() { hyprctl keyword monitor "$1" >/dev/null 2>&1 || true; }

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

save_profile() {
    mkdir -p "$STATE_DIR"
    printf '%s\n' "$1" >"$PROFILE_FILE"
}

current_profile() {
    if [[ -f "$PROFILE_FILE" ]]; then tr -d '[:space:]' <"$PROFILE_FILE"; else echo ""; fi
}

# Lines like `monitor = DP-2,2560x1440@143.91,0x0,1` or `monitor=eDP-1,...`
monitor_lines() {
    local file="$1" line spec
    [[ -f "$file" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -n "$line" ]] || continue
        [[ "$line" == monitor* ]] || continue
        spec="${line#monitor}"
        spec="${spec#"${spec%%[![:space:]=]*}"}"
        spec="${spec#=}"
        spec="${spec#"${spec%%[![:space:]]*}"}"
        spec="${spec%"${spec##*[![:space:]]}"}"
        [[ -n "$spec" ]] || continue
        printf '%s\n' "$spec"
    done <"$file"
}

monitor_name() {
    local spec="$1"
    printf '%s\n' "${spec%%,*}"
}

monitor_is_disabled() {
    local spec="$1"
    [[ "${spec#*,}" == disable ]]
}

profile_conf() {
    local profile="${1:-}"
    local file
    if [[ -n "$profile" && "$profile" != default ]]; then
        file="${MONITORS_D}/${HOST}-${profile}.conf"
        [[ -f "$file" ]] && { printf '%s\n' "$file"; return 0; }
    fi
    file="${MONITORS_D}/${HOST}.conf"
    [[ -f "$file" ]] && { printf '%s\n' "$file"; return 0; }
    file="${MONITORS_D}/default.conf"
    [[ -f "$file" ]] && { printf '%s\n' "$file"; return 0; }
    return 1
}

host_profiles() {
    local file name
    shopt -s nullglob
    if [[ -f "${MONITORS_D}/${HOST}.conf" ]]; then
        printf '%s\n' "default"
    fi
    for file in "${MONITORS_D}/${HOST}-"*.conf; do
        name="$(basename "$file" .conf)"
        printf '%s\n' "${name#${HOST}-}"
    done
    shopt -u nullglob
}

apply_monitor_conf() {
    local file="$1" spec
    [[ -f "$file" ]] || { echo "missing monitor conf: $file" >&2; return 1; }
    while IFS= read -r spec; do
        [[ -n "$spec" ]] || continue
        keyword_monitor "$spec"
    done < <(monitor_lines "$file")
}

monitor_spec_from_conf() {
    local file="$1" mon="$2" spec name
    while IFS= read -r spec; do
        name="$(monitor_name "$spec")"
        if [[ "$name" == "$mon" ]]; then
            printf '%s\n' "$spec"
            return 0
        fi
    done < <(monitor_lines "$file")
    return 1
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

default_profile_for_host() {
    local first="" name
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        if [[ "$name" == desk ]]; then
            printf '%s\n' "desk"
            return 0
        fi
        [[ -n "$first" ]] || first="$name"
    done < <(host_profiles)
    printf '%s\n' "${first:-default}"
}

apply_profile() {
    local profile="${1:-}"
    local file
    if [[ -z "$profile" || "$profile" == default ]]; then
        profile="$(default_profile_for_host)"
    fi
    file="$(profile_conf "$profile")" || {
        echo "no monitor conf for ${HOST}/${profile}" >&2
        return 1
    }
    apply_monitor_conf "$file"
    case "$profile" in
        theater) apply_theater_audio ;;
        desk|workshare) restore_desk_audio ;;
    esac
    save_profile "$profile"
    notify "Display profile: ${HOST}/${profile}"
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
    if m.get("disabled") is True:
        raise SystemExit(1)
    if int(m.get("width") or 0) <= 0:
        raise SystemExit(1)
    raise SystemExit(0)
raise SystemExit(1)
' "$mon" 2>/dev/null
}

monitor_center() {
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
    x = int(m.get("x") or 0)
    y = int(m.get("y") or 0)
    w = int(m.get("width") or 0)
    h = int(m.get("height") or 0)
    print(x + max(w // 2, 1), y + max(h // 2, 1))
    raise SystemExit(0)
raise SystemExit(1)
' "$mon" 2>/dev/null
}

refresh_cursor() {
    local mon="${1:-}" pos
    hyprctl keyword cursor:no_hardware_cursors 1 >/dev/null 2>&1 || true
    sleep 0.05
    hyprctl keyword cursor:no_hardware_cursors 0 >/dev/null 2>&1 || true
    if [[ -n "$mon" ]] && pos="$(monitor_center "$mon" || true)" && [[ -n "$pos" ]]; then
        # shellcheck disable=SC2086
        hyprctl dispatch movecursor $pos >/dev/null 2>&1 || true
    else
        hyprctl dispatch movecursor 1 1 >/dev/null 2>&1 || true
    fi
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
    for i in $(seq 1 20); do
        monitor_is_live "$mon" && return 0
        sleep 0.25
    done
    return 1
}

workspaces_restored() {
    local mon="$1"
    local wanted actual
    wanted="$(awk -F= '/^workspace=/{print $2}' "$SAVED_WS_FILE" | sort)"
    [[ -n "$wanted" ]] || return 0
    actual="$(workspaces_on_monitor "$mon" | sort)"
    [[ "$wanted" == "$actual" ]]
}

restore_saved_workspaces_now() {
    [[ -f "$SAVED_WS_FILE" ]] || return 0
    local mon ws
    mon="$(awk -F= '/^monitor=/{print $2; exit}' "$SAVED_WS_FILE")"
    [[ -n "$mon" ]] || return 0
    wait_for_monitor "$mon" || return 1
    while IFS= read -r ws; do
        [[ -n "$ws" ]] || continue
        hyprctl dispatch moveworkspacetomonitor "$ws" "$mon" >/dev/null 2>&1 || true
    done < <(awk -F= '/^workspace=/{print $2}' "$SAVED_WS_FILE")
    if workspaces_restored "$mon"; then
        rm -f "$SAVED_WS_FILE"
        return 0
    fi
    return 1
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
    (
        wait_for_unlock
        local i
        for i in 1 2 3 4 5 6; do
            restore_saved_workspaces_now && break
            sleep 1
        done
        rm -f "$RESTORE_WS_PID_FILE"
    ) &
    mkdir -p "$STATE_DIR"
    echo $! >"$RESTORE_WS_PID_FILE"
}

cmd_restore_ws() { need_hypr; QUIET=1; schedule_workspace_restore; }

cmd_apply() {
    need_hypr
    QUIET=1
    with_apply_lock || return 0
    local profile
    profile="$(current_profile)"
    apply_profile "$profile"
    release_apply_lock
    schedule_workspace_restore
}

cmd_set() {
    local profile="$1"
    need_hypr
    with_apply_lock || return 0
    if ! profile_conf "$profile" >/dev/null; then
        notify "No ${HOST}-${profile}.conf (this host is ${HOST})"
        apply_profile "$(current_profile)"
        release_apply_lock
        return 0
    fi
    apply_profile "$profile"
    release_apply_lock
    schedule_workspace_restore
}

current_conf() {
    profile_conf "$(current_profile)" || profile_conf "$(default_profile_for_host)"
}

desk_dp_in_use() {
    local file spec name
    file="$(current_conf)" || return 1
    while IFS= read -r spec; do
        name="$(monitor_name "$spec")"
        case "$name" in
            DP-2|DP-3)
                monitor_is_disabled "$spec" && return 1
                return 0
                ;;
        esac
    done < <(monitor_lines "$file")
    return 1
}

dpms_desk_ports() {
    local action="$1" mon
    desk_dp_in_use || return 0
    for mon in "${RUNEWYRM_DP_MONITORS[@]}"; do
        dpms "$action" "$mon"
    done
}

enable_idle_monitor() {
    local file spec i
    file="$(current_conf)" || return 1
    spec="$(monitor_spec_from_conf "$file" "$RUNEWYRM_IDLE_MONITOR" || true)"
    [[ -n "$spec" ]] || return 1
    monitor_is_disabled "$spec" && return 0
    for i in $(seq 1 12); do
        keyword_monitor "$spec"
        dpms on "$RUNEWYRM_IDLE_MONITOR"
        monitor_is_live "$RUNEWYRM_IDLE_MONITOR" && return 0
        sleep 0.4
    done
    return 1
}

idle_off_runewyrm() {
    save_monitor_workspaces "$RUNEWYRM_IDLE_MONITOR"
    dpms off "$RUNEWYRM_IDLE_MONITOR"
    dpms_desk_ports off
    sleep 0.2
    keyword_monitor "${RUNEWYRM_IDLE_MONITOR},disable"
}

idle_off_other() { dpms off; }

cmd_idle_off() {
    need_hypr
    QUIET=1
    with_apply_lock || return 0
    case "$HOST" in
        runewyrm) idle_off_runewyrm ;;
        *) idle_off_other ;;
    esac
    release_apply_lock
}

cmd_idle_on() {
    need_hypr
    QUIET=1
    with_apply_lock || return 0
    # DRM is often still coming back after sleep. Give it a beat.
    sleep 0.3
    dpms on
    dpms_desk_ports on
    if [[ "$HOST" == "runewyrm" ]]; then
        enable_idle_monitor || true
        release_apply_lock
        schedule_workspace_restore
        refresh_cursor "$RUNEWYRM_IDLE_MONITOR"
    else
        release_apply_lock
        refresh_cursor
    fi
}

cmd_status() {
    local file
    file="$(current_conf || true)"
    printf 'host:            %s\n' "$HOST"
    printf 'saved profile:   %s\n' "$(current_profile)"
    printf 'conf:            %s\n' "${file:-none}"
    printf 'lock:            %s\n' "$APPLY_LOCK_FILE"
    printf 'default sink:    %s\n' "$(default_sink)"
    if [[ -n "$file" ]]; then
        printf 'monitors:\n'
        monitor_lines "$file" | sed 's/^/  /'
    fi
    if [[ -f "$SAVED_WS_FILE" ]]; then
        printf 'pending ws:\n'
        sed 's/^/  /' "$SAVED_WS_FILE"
    fi
}

cmd_list() {
    local names
    names="$(host_profiles | paste -sd ', ' -)"
    if [[ -n "$names" ]]; then
        printf '%s profiles: %s\n' "$HOST" "$names"
    else
        printf '%s: default.conf fallback\n' "$HOST"
    fi
}

usage() { echo "Usage: display-profile.sh [apply|idle-off|idle-on|restore-ws|status|list|<profile>]"; }

main() {
    local cmd="${1:-apply}"
    case "$cmd" in
        apply|"") cmd_apply ;;
        idle-off) cmd_idle_off ;;
        idle-on) cmd_idle_on ;;
        restore-ws) cmd_restore_ws ;;
        status) cmd_status ;;
        list) cmd_list ;;
        -h|--help|help) usage ;;
        *) cmd_set "$cmd" ;;
    esac
}

main "$@"
