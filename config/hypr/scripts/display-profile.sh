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
    notify "Display profile: ${HOST}/${profile}"
}

workspace_map_dump() {
    hyprctl workspaces -j 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)
for w in data:
    mon = w.get("monitor") or ""
    if not mon:
        continue
    name = str(w.get("name") or "")
    wid = w.get("id")
    key = name if name.startswith("special") else (str(wid) if wid is not None else name)
    if not key:
        continue
    print(f"workspace={key}:{mon}")
' 2>/dev/null || true
    hyprctl monitors -j 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)
for m in data:
    name = m.get("name") or ""
    ws = (m.get("activeWorkspace") or {}).get("name") or (m.get("activeWorkspace") or {}).get("id")
    if name and ws is not None and str(ws) != "":
        print(f"active={name}:{ws}")
' 2>/dev/null || true
}

save_workspace_map() {
    mkdir -p "$STATE_DIR"
    workspace_map_dump >"$SAVED_WS_FILE"
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

wait_for_monitor() {
    local mon="$1" i
    for i in $(seq 1 20); do
        monitor_is_live "$mon" && return 0
        sleep 0.25
    done
    return 1
}

layout_ready() {
    local file spec name
    file="$(current_conf)" || return 1
    while IFS= read -r spec; do
        [[ -n "$spec" ]] || continue
        monitor_is_disabled "$spec" && continue
        name="$(monitor_name "$spec")"
        monitor_is_live "$name" || return 1
    done < <(monitor_lines "$file")
    return 0
}

workspace_on_monitor() {
    local ws="$1" mon="$2"
    hyprctl workspaces -j 2>/dev/null | python3 -c '
import json, sys
ws, mon = sys.argv[1], sys.argv[2]
try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(1)
for w in data:
    name = str(w.get("name") or "")
    wid = str(w.get("id") if w.get("id") is not None else "")
    if ws not in (name, wid):
        continue
    raise SystemExit(0 if (w.get("monitor") or "") == mon else 1)
raise SystemExit(1)
' "$ws" "$mon" 2>/dev/null
}

workspaces_restored() {
    local line ws mon
    [[ -f "$SAVED_WS_FILE" ]] || return 0
    while IFS= read -r line; do
        [[ "$line" == workspace=* ]] || continue
        ws="${line#workspace=}"
        mon="${ws##*:}"
        ws="${ws%:*}"
        [[ -n "$ws" && -n "$mon" ]] || continue
        workspace_on_monitor "$ws" "$mon" || return 1
    done <"$SAVED_WS_FILE"
    return 0
}

restore_saved_workspaces_now() {
    [[ -f "$SAVED_WS_FILE" ]] || return 0
    local line ws mon
    while IFS= read -r line; do
        [[ "$line" == workspace=* ]] || continue
        ws="${line#workspace=}"
        mon="${ws##*:}"
        ws="${ws%:*}"
        [[ -n "$ws" && -n "$mon" ]] || continue
        wait_for_monitor "$mon" || return 1
        hyprctl dispatch moveworkspacetomonitor "$ws" "$mon" >/dev/null 2>&1 || true
    done <"$SAVED_WS_FILE"
    while IFS= read -r line; do
        [[ "$line" == active=* ]] || continue
        mon="${line#active=}"
        ws="${mon##*:}"
        mon="${mon%:*}"
        [[ -n "$ws" && -n "$mon" ]] || continue
        hyprctl dispatch focusmonitor "$mon" >/dev/null 2>&1 || true
        hyprctl dispatch workspace "$ws" >/dev/null 2>&1 || true
    done <"$SAVED_WS_FILE"
    if workspaces_restored; then
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
        local i
        for i in $(seq 1 16); do
            restore_saved_workspaces_now && break
            sleep 0.4
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

# HDMI wakes itself from DPMS-only. Disable it after the workspace map is saved.
idle_off_runewyrm() {
    save_workspace_map
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
    sleep 1
    local i file
    file="$(current_conf || true)"
    for i in $(seq 1 10); do
        dpms on
        dpms_desk_ports on
        [[ -n "$file" ]] && apply_monitor_conf "$file"
        if [[ "$HOST" == "runewyrm" ]]; then
            enable_idle_monitor || true
        fi
        layout_ready && break
        sleep 0.5
    done
    restore_saved_workspaces_now || true
    release_apply_lock
    schedule_workspace_restore
    if [[ "$HOST" == "runewyrm" ]]; then
        refresh_cursor "$RUNEWYRM_IDLE_MONITOR"
    else
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
