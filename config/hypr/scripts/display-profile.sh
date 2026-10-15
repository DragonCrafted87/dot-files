#!/usr/bin/env bash
# Apply Hyprland monitor layouts from conf.d/monitors.d/*.conf.
# Profile state and audio live in display-switch.sh / display-audio.sh.
set -euo pipefail

HOST="$(hostname -s 2>/dev/null || hostname)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITORS_D="${SCRIPT_DIR}/../conf.d/monitors.d"
HOSTS_D="${SCRIPT_DIR}/../conf.d/hosts.d"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
PROFILE_FILE="${STATE_DIR}/display-profile"
SAVED_WS_FILE="${STATE_DIR}/saved-monitor-workspaces"
RESTORE_WS_PID_FILE="${STATE_DIR}/restore-ws.pid"
APPLY_LOCK_FILE="${STATE_DIR}/apply.lock"
IDLE_DISABLED_FILE="${STATE_DIR}/idle-monitor-disabled"
# lua/monitors.lua re-reads this on reload. Eval'd monitor rules are
# cleared, and this file is how the last layout survives.
RUNTIME_MONITORS_FILE="${STATE_DIR}/monitors.runtime.conf"
IDLE_MONITOR=""
DESK_PORTS=""
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

trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s\n' "$s"
}

load_host_conf() {
    local file="${HOSTS_D}/${HOST}.conf" line key val
    IDLE_MONITOR=""
    DESK_PORTS=""
    [[ -f "$file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="$(trim "$line")"
        [[ -n "$line" && "$line" == *=* ]] || continue
        key="$(trim "${line%%=*}")"
        val="$(trim "${line#*=}")"
        case "$key" in
            IDLE_MONITOR) IDLE_MONITOR="$val" ;;
            DESK_PORTS) DESK_PORTS="$val" ;;
        esac
    done <"$file"
}

# hyprctl keyword monitor wants 2560x1440@143.91, not @143.91Hz.
normalize_monitor_spec() {
    printf '%s\n' "$1" | sed 's/@\([0-9.][0-9.]*\)Hz,/@\1,/'
}

# Lua configs reject hyprctl keyword (exit 0, prints "Use eval").
HYPRCTL_LUA=""

hyprctl_is_lua() {
    local out
    if [[ -n "$HYPRCTL_LUA" ]]; then
        [[ "$HYPRCTL_LUA" == "1" ]]
        return
    fi
    out="$(hyprctl keyword misc:disable_xdg_env_checks true 2>&1 || true)"
    if [[ "$out" == *"Use eval"* ]]; then
        HYPRCTL_LUA=1
    else
        HYPRCTL_LUA=0
    fi
    [[ "$HYPRCTL_LUA" == "1" ]]
}

lua_monitor_stmt() {
    local spec name rest mode pos scale
    spec="$(normalize_monitor_spec "$1")"
    name="${spec%%,*}"
    rest="${spec#"${name}"}"
    rest="${rest#,}"
    if [[ "$rest" == "disable" || "$rest" == "disabled" ]]; then
        printf 'hl.monitor({ output = %s, disabled = true })' "$(lua_str "$name")"
        return 0
    fi
    mode="${rest%%,*}"
    rest="${rest#"${mode}"}"
    rest="${rest#,}"
    pos="${rest%%,*}"
    rest="${rest#"${pos}"}"
    rest="${rest#,}"
    scale="${rest%%,*}"
    printf 'hl.monitor({ output = %s, disabled = false, mode = %s, position = %s, scale = %s })' \
        "$(lua_str "$name")" "$(lua_str "$mode")" "$(lua_str "$pos")" "$(lua_str "$scale")"
}

keyword_monitor() {
    local spec
    spec="$(normalize_monitor_spec "$1")"
    if ! hyprctl_is_lua; then
        hyprctl keyword monitor "$spec" >/dev/null 2>&1 || true
        return 0
    fi
    hyprctl eval "$(lua_monitor_stmt "$spec")" >/dev/null 2>&1 || true
}

# One eval so 0.56 does not warn about overlap while HDMI is still at 0x0.
# Enabled outputs are applied right-to-left so the single-head panel moves
# off 0x0 before DP-2 lands there.
apply_lua_monitors() {
    local file="$1" spec pos x stmt joined=""
    local -a enable_lines=() disable_stmts=() stmts=()
    while IFS= read -r spec; do
        [[ -n "$spec" ]] || continue
        spec="$(normalize_monitor_spec "$spec")"
        if monitor_is_disabled "$spec"; then
            disable_stmts+=("$(lua_monitor_stmt "$spec")")
            continue
        fi
        pos="$(printf '%s\n' "${spec#*,}" | cut -d, -f2)"
        x="${pos%%x*}"
        [[ "$x" =~ ^-?[0-9]+$ ]] || x=0
        enable_lines+=("$x $spec")
    done < <(monitor_lines "$file")
    if ((${#enable_lines[@]} > 0)); then
        while IFS= read -r spec; do
            [[ -n "$spec" ]] || continue
            spec="${spec#* }"
            stmts+=("$(lua_monitor_stmt "$spec")")
        done < <(printf '%s\n' "${enable_lines[@]}" | sort -nr -k1,1)
    fi
    stmts+=("${disable_stmts[@]}")
    ((${#stmts[@]} > 0)) || return 0
    for stmt in "${stmts[@]}"; do
        joined+="${stmt}; "
    done
    hyprctl eval "$joined" >/dev/null 2>&1 || true
}

lua_str() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '"%s"' "$s"
}

hypr_dispatch() {
    if hyprctl_is_lua; then
        hyprctl dispatch "$1" >/dev/null 2>&1 || true
        return 0
    fi
    shift
    hyprctl dispatch "$@" >/dev/null 2>&1 || true
}

keyword_option() {
    local key="$1" val="$2" cat opt
    if ! hyprctl_is_lua; then
        hyprctl keyword "$key" "$val" >/dev/null 2>&1 || true
        return 0
    fi
    cat="${key%%:*}"
    opt="${key#*:}"
    case "$val" in
        1 | true | on) val=true ;;
        0 | false | off) val=false ;;
    esac
    hyprctl eval "hl.config({ ${cat} = { ${opt} = ${val} } })" >/dev/null 2>&1 || true
}

dpms() {
    local action="$1"
    local mon="${2:-}"
    if [[ -n "$mon" ]]; then
        hypr_dispatch "hl.dsp.dpms({ action = $(lua_str "$action"), monitor = $(lua_str "$mon") })" dpms "$action" "$mon"
    else
        hypr_dispatch "hl.dsp.dpms({ action = $(lua_str "$action") })" dpms "$action"
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
    local rest="${1#*,}"
    [[ "$rest" == "disable" || "$rest" == "disabled" ]]
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

write_runtime_monitors() {
    local file="$1" spec
    mkdir -p "$STATE_DIR"
    {
        printf '# Generated by display-profile.sh. Do not edit.\n'
        printf '# Hyprland sources this on reload so outputs keep their last layout.\n'
        while IFS= read -r spec; do
            [[ -n "$spec" ]] || continue
            printf 'monitor=%s\n' "$(normalize_monitor_spec "$spec")"
        done < <(monitor_lines "$file")
    } >"$RUNTIME_MONITORS_FILE"
}

wait_conf_layout() {
    local file="$1" spec name i
    [[ -f "$file" ]] || return 1
    for i in $(seq 1 20); do
        local ready=1
        while IFS= read -r spec; do
            [[ -n "$spec" ]] || continue
            monitor_is_disabled "$spec" && continue
            name="$(monitor_name "$spec")"
            if ! monitor_is_live "$name"; then
                ready=0
                break
            fi
        done < <(monitor_lines "$file")
        [[ "$ready" -eq 1 ]] && return 0
        sleep 0.25
    done
    return 1
}

apply_monitor_conf() {
    local file="$1" spec
    [[ -f "$file" ]] || { echo "missing monitor conf: $file" >&2; return 1; }
    write_runtime_monitors "$file"
    if hyprctl_is_lua; then
        apply_lua_monitors "$file"
    else
        while IFS= read -r spec; do
            [[ -n "$spec" ]] || continue
            keyword_monitor "$spec"
        done < <(monitor_lines "$file")
    fi
    wait_conf_layout "$file" || true
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
    if name.startswith("special") or (name and (wid is None or name != str(wid))):
        key = name
    elif wid is not None and not str(wid).startswith("-"):
        key = str(wid)
    else:
        key = ""
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
    keyword_option cursor:no_hardware_cursors 1
    sleep 0.05
    keyword_option cursor:no_hardware_cursors 0
    if [[ -n "$mon" ]] && pos="$(monitor_center "$mon" || true)" && [[ -n "$pos" ]]; then
        read -r cx cy <<<"$pos"
        hypr_dispatch "hl.dsp.cursor.move({ x = ${cx}, y = ${cy} })" movecursor "$cx" "$cy"
    else
        hypr_dispatch "hl.dsp.cursor.move({ x = 1, y = 1 })" movecursor 1 1
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

# Resolve a negative id left by an older map. Return 1 when that id is gone
# so the restore check does not retry forever on a workspace that no longer exists.
workspace_name_for_id() {
    local id="$1"
    hyprctl workspaces -j 2>/dev/null | python3 -c '
import json, sys
want = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(1)
for w in data:
    wid = w.get("id")
    if wid is None or str(wid) != want:
        continue
    name = str(w.get("name") or "")
    if not name or name == want:
        raise SystemExit(1)
    print(name)
    raise SystemExit(0)
raise SystemExit(1)
' "$id" 2>/dev/null
}

# Dispatch form for one saved key. A leading "-" must not be returned:
# Hyprland adds that number to the focused workspace id and clamps at 1,
# so "-1337" moves workspace 1 instead of code-1.
workspace_selector() {
    local key="$1" name
    if [[ "$key" =~ ^[0-9]+$ || "$key" == special:* ]]; then
        printf '%s\n' "$key"
        return 0
    fi
    if [[ "$key" =~ ^-[0-9]+$ ]]; then
        name="$(workspace_name_for_id "$key")" || return 1
        printf 'name:%s\n' "$name"
        return 0
    fi
    printf 'name:%s\n' "$key"
}

monitor_active_name() {
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
    ws = m.get("activeWorkspace") or {}
    name = ws.get("name")
    if name is None or str(name) == "":
        name = ws.get("id")
    if name is None or str(name) == "":
        raise SystemExit(1)
    print(name)
    raise SystemExit(0)
raise SystemExit(1)
' "$mon" 2>/dev/null
}

workspaces_restored() {
    local line ws mon token
    [[ -f "$SAVED_WS_FILE" ]] || return 0
    while IFS= read -r line; do
        [[ "$line" == workspace=* ]] || continue
        ws="${line#workspace=}"
        mon="${ws##*:}"
        ws="${ws%:*}"
        [[ -n "$ws" && -n "$mon" ]] || continue
        token="$(workspace_selector "$ws")" || continue
        token="${token#name:}"
        workspace_on_monitor "$token" "$mon" || return 1
    done <"$SAVED_WS_FILE"
    return 0
}

restore_saved_workspaces_now() {
    [[ -f "$SAVED_WS_FILE" ]] || return 0
    local line ws mon sel token active
    while IFS= read -r line; do
        [[ "$line" == workspace=* ]] || continue
        ws="${line#workspace=}"
        mon="${ws##*:}"
        ws="${ws%:*}"
        [[ -n "$ws" && -n "$mon" ]] || continue
        sel="$(workspace_selector "$ws")" || continue
        token="${sel#name:}"
        if workspace_on_monitor "$token" "$mon"; then
            continue
        fi
        wait_for_monitor "$mon" || return 1
        hypr_dispatch "hl.dsp.workspace.move({ workspace = $(lua_str "$sel"), monitor = $(lua_str "$mon") })" moveworkspacetomonitor "$sel" "$mon"
    done <"$SAVED_WS_FILE"
    while IFS= read -r line; do
        [[ "$line" == active=* ]] || continue
        mon="${line#active=}"
        ws="${mon##*:}"
        mon="${mon%:*}"
        [[ -n "$ws" && -n "$mon" ]] || continue
        active="$(monitor_active_name "$mon" || true)"
        if [[ "$active" == "$ws" ]]; then
            continue
        fi
        sel="$(workspace_selector "$ws")" || continue
        hypr_dispatch "hl.dsp.focus({ monitor = $(lua_str "$mon") })" focusmonitor "$mon"
        hypr_dispatch "hl.dsp.focus({ workspace = $(lua_str "$sel") })" workspace "$sel"
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

desk_ports_in_use() {
    local file spec name port
    [[ -n "$DESK_PORTS" ]] || return 1
    file="$(current_conf)" || return 1
    while IFS= read -r spec; do
        [[ -n "$spec" ]] || continue
        monitor_is_disabled "$spec" && continue
        name="$(monitor_name "$spec")"
        for port in $DESK_PORTS; do
            if [[ "$name" == "$port" ]]; then
                return 0
            fi
        done
    done < <(monitor_lines "$file")
    return 1
}

dpms_desk_ports() {
    local action="$1" mon
    desk_ports_in_use || return 0
    for mon in $DESK_PORTS; do
        dpms "$action" "$mon"
    done
}

profile_has_other_enabled() {
    local file="$1" spec name
    [[ -f "$file" ]] || return 1
    while IFS= read -r spec; do
        [[ -n "$spec" ]] || continue
        monitor_is_disabled "$spec" && continue
        name="$(monitor_name "$spec")"
        [[ "$name" == "$IDLE_MONITOR" ]] && continue
        [[ -n "$name" ]] || continue
        return 0
    done < <(monitor_lines "$file")
    return 1
}

enable_idle_monitor() {
    local file spec i
    [[ -n "$IDLE_MONITOR" ]] || return 0
    file="$(current_conf)" || return 1
    spec="$(monitor_spec_from_conf "$file" "$IDLE_MONITOR" || true)"
    [[ -n "$spec" ]] || return 1
    monitor_is_disabled "$spec" && return 0
    for i in $(seq 1 12); do
        keyword_monitor "$spec"
        dpms on "$IDLE_MONITOR"
        monitor_is_live "$IDLE_MONITOR" && return 0
        sleep 0.4
    done
    return 1
}

# HDMI (IDLE_MONITOR) can wake itself from DPMS-only, so desk layouts
# disable that connector after the workspace map is saved. Single-output
# layouts must keep the remaining wl_output; dropping it kills clients.
idle_off_idle_monitor() {
    local file
    save_workspace_map
    dpms off "$IDLE_MONITOR"
    dpms_desk_ports off
    file="$(current_conf || true)"
    if [[ -n "$file" ]] && profile_has_other_enabled "$file"; then
        sleep 0.2
        keyword_monitor "${IDLE_MONITOR},disable"
        mkdir -p "$STATE_DIR"
        printf '1\n' >"$IDLE_DISABLED_FILE"
    else
        rm -f "$IDLE_DISABLED_FILE"
    fi
}

idle_off_other() { dpms off; }

cmd_idle_off() {
    need_hypr
    QUIET=1
    with_apply_lock || return 0
    if [[ -n "$IDLE_MONITOR" ]]; then
        idle_off_idle_monitor
    else
        idle_off_other
    fi
    release_apply_lock
}

cmd_idle_on() {
    need_hypr
    QUIET=1
    with_apply_lock || return 0
    local file
    file="$(current_conf || true)"
    dpms on
    dpms_desk_ports on
    if [[ -f "$IDLE_DISABLED_FILE" ]]; then
        sleep 1
        if enable_idle_monitor; then
            rm -f "$IDLE_DISABLED_FILE"
        fi
        if [[ -n "$file" ]]; then
            wait_conf_layout "$file" || true
        fi
    fi
    restore_saved_workspaces_now || true
    release_apply_lock
    schedule_workspace_restore
    if [[ -n "$IDLE_MONITOR" ]] && monitor_is_live "$IDLE_MONITOR"; then
        refresh_cursor "$IDLE_MONITOR"
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
    load_host_conf
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

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
