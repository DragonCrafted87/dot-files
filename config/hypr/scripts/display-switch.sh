#!/usr/bin/env bash
# HDMI-switch helper for hosts with SINGLE_PROFILES in hosts.d/<host>.conf.
# Owns saved profile state. Calls display-profile.sh and display-audio.sh.
# Watch is daemonized only while a single-output profile is active.
set -euo pipefail

HOST="$(hostname -s 2>/dev/null || hostname)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_SH="${SCRIPT_DIR}/display-profile.sh"
MONITORS_D="${SCRIPT_DIR}/../conf.d/monitors.d"
HOSTS_D="${SCRIPT_DIR}/../conf.d/hosts.d"
AUDIO_SH="${SCRIPT_DIR}/display-audio.sh"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
PROFILE_FILE="${STATE_DIR}/display-profile"
WATCH_PID_FILE="${STATE_DIR}/display-switch.pid"

IDLE_MONITOR=""
DESK_PORTS=""
SWITCH_PORT=""
SWITCH_DRM=""
SINGLE_PROFILES=""
DEFAULT_SINGLE_PROFILE=""

trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s\n' "$s"
}

load_host_conf() {
    local file="${HOSTS_D}/${HOST}.conf" line key val
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
            SWITCH_PORT) SWITCH_PORT="$val" ;;
            SWITCH_DRM) SWITCH_DRM="$val" ;;
            SINGLE_PROFILES) SINGLE_PROFILES="$val" ;;
            DEFAULT_SINGLE_PROFILE) DEFAULT_SINGLE_PROFILE="$val" ;;
        esac
    done <"$file"
}

current_profile() {
    if [[ -f "$PROFILE_FILE" ]]; then tr -d '[:space:]' <"$PROFILE_FILE"; else echo ""; fi
}

save_profile() {
    mkdir -p "$STATE_DIR"
    printf '%s\n' "$1" >"$PROFILE_FILE"
}

profile_match_desc() {
    local profile="$1" file line val
    file="${MONITORS_D}/${HOST}-${profile}.conf"
    [[ -f "$file" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="$(trim "$line")"
        [[ "$line" == MATCH_DESC=* ]] || continue
        val="$(trim "${line#MATCH_DESC=}")"
        [[ -n "$val" ]] || continue
        printf '%s\n' "$val"
        return 0
    done <"$file"
    return 1
}

drm_dir() {
    local name="${SWITCH_DRM:-}" port="${SWITCH_PORT:-HDMI-A-1}" d
    if [[ -n "$name" && -d "/sys/class/drm/${name}" ]]; then
        printf '%s\n' "/sys/class/drm/${name}"
        return 0
    fi
    shopt -s nullglob
    for d in /sys/class/drm/card*-"${port}"; do
        if [[ -d "$d" ]]; then
            printf '%s\n' "$d"
            shopt -u nullglob
            return 0
        fi
    done
    shopt -u nullglob
    return 1
}

drm_fingerprint() {
    local dir status edid
    dir="$(drm_dir || true)"
    [[ -n "$dir" ]] || { echo none; return 0; }
    status="$(tr -d '[:space:]' <"${dir}/status" 2>/dev/null || echo missing)"
    if command -v md5sum >/dev/null 2>&1 && [[ -r "${dir}/edid" ]]; then
        edid="$(md5sum "${dir}/edid" 2>/dev/null | awk '{print $1}')"
    else
        edid="$(wc -c <"${dir}/edid" 2>/dev/null || echo 0)"
    fi
    printf '%s:%s\n' "$status" "${edid:-0}"
}

switch_port_identity() {
    local port="${SWITCH_PORT:-}"
    [[ -n "$port" ]] || return 1
    hyprctl monitors -j 2>/dev/null | python3 -c '
import json, sys
port = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(1)
for m in data:
    if m.get("name") != port:
        continue
    if m.get("disabled") is True:
        raise SystemExit(1)
    if int(m.get("width") or 0) <= 0:
        raise SystemExit(1)
    parts = [
        str(m.get("description") or ""),
        str(m.get("make") or ""),
        str(m.get("model") or ""),
        str(m.get("serial") or ""),
    ]
    print(" ".join(parts))
    raise SystemExit(0)
raise SystemExit(1)
' "$port" 2>/dev/null
}

detect_single_profile() {
    local identity="" profile needle
    identity="$(switch_port_identity || true)"
    [[ -n "$identity" ]] || return 1
    for profile in $SINGLE_PROFILES; do
        needle="$(profile_match_desc "$profile" || true)"
        [[ -n "$needle" ]] || continue
        if grep -Fiq "$needle" <<<"$identity"; then
            printf '%s\n' "$profile"
            return 0
        fi
    done
    [[ -n "$DEFAULT_SINGLE_PROFILE" ]] || return 1
    printf '%s\n' "$DEFAULT_SINGLE_PROFILE"
}

is_single_profile() {
    local profile="$1" name
    [[ -n "$profile" ]] || return 1
    for name in $SINGLE_PROFILES; do
        [[ "$name" == "$profile" ]] && return 0
    done
    return 1
}

apply_profile() {
    local profile="${1:-}"
    [[ -n "$profile" ]] || return 1
    "$PROFILE_SH" "$profile"
    if [[ -x "$AUDIO_SH" ]]; then
        "$AUDIO_SH" "$profile" || true
    fi
    save_profile "$profile"
}

watch_pid() {
    [[ -f "$WATCH_PID_FILE" ]] || return 1
    tr -d '[:space:]' <"$WATCH_PID_FILE"
}

watch_running() {
    local pid
    pid="$(watch_pid || true)"
    [[ -n "$pid" ]] || return 1
    kill -0 "$pid" 2>/dev/null
}

stop_watch() {
    local pid
    pid="$(watch_pid || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill -- "-${pid}" 2>/dev/null || kill "$pid" 2>/dev/null || true
        pkill -P "$pid" >/dev/null 2>&1 || true
    fi
    rm -f "$WATCH_PID_FILE"
}

start_watch() {
    is_single_profile "$(current_profile)" || return 0
    if watch_running; then
        return 0
    fi
    if ! command -v inotifywait >/dev/null 2>&1; then
        echo "display-switch: inotifywait missing; install inotify-tools" >&2
        return 1
    fi
    mkdir -p "$STATE_DIR"
    setsid "$0" watch </dev/null >/dev/null 2>&1 &
    echo $! >"$WATCH_PID_FILE"
}

wait_drm_event() {
    local dir targets=()
    dir="$(drm_dir || true)"
    [[ -n "$dir" ]] || return 1
    [[ -e "${dir}/status" ]] && targets+=("${dir}/status")
    [[ -e "${dir}/edid" ]] && targets+=("${dir}/edid")
    targets+=("$dir")
    if command -v inotifywait >/dev/null 2>&1; then
        inotifywait -q -e modify,attrib,close_write,moved_to -- "${targets[@]}" >/dev/null 2>&1 || true
        return 0
    fi
    echo "display-switch: inotifywait missing; install inotify-tools" >&2
    return 1
}

settle_after_event() {
    local i
    for i in $(seq 1 16); do
        switch_port_identity >/dev/null && return 0
        sleep 0.25
    done
    return 1
}

cmd_watch() {
    local last fp detected
    mkdir -p "$STATE_DIR"
    echo $$ >"$WATCH_PID_FILE"
    last="$(drm_fingerprint)"
    while is_single_profile "$(current_profile)"; do
        wait_drm_event || break
        is_single_profile "$(current_profile)" || break
        settle_after_event || continue
        fp="$(drm_fingerprint)"
        [[ "$fp" == "$last" ]] && continue
        last="$fp"
        [[ "$fp" == disconnected:* || "$fp" == missing:* ]] && continue
        detected="$(detect_single_profile || true)"
        [[ -n "$detected" ]] || continue
        apply_profile "$detected" || true
    done
    rm -f "$WATCH_PID_FILE"
}

cmd_single() {
    local profile
    profile="$(detect_single_profile || true)"
    profile="${profile:-$DEFAULT_SINGLE_PROFILE}"
    if [[ -z "$profile" ]]; then
        echo "display-switch: no HDMI panel matched on ${HOST}" >&2
        return 1
    fi
    apply_profile "$profile"
    start_watch
}

cmd_desk() {
    stop_watch
    apply_profile desk
}

cmd_set() {
    local profile="$1"
    if is_single_profile "$profile"; then
        apply_profile "$profile"
        start_watch
        return 0
    fi
    stop_watch
    apply_profile "$profile"
}

cmd_restore() {
    local profile
    profile="$(current_profile)"
    [[ -n "$profile" ]] || profile=desk
    if is_single_profile "$profile"; then
        cmd_set "$profile"
    else
        cmd_desk
    fi
}

cmd_status() {
    local dir pid="stopped"
    dir="$(drm_dir || true)"
    if watch_running; then
        pid="$(watch_pid)"
    fi
    printf 'host:            %s\n' "$HOST"
    printf 'saved profile:   %s\n' "$(current_profile)"
    printf 'switch port:     %s\n' "${SWITCH_PORT:-none}"
    printf 'drm path:        %s\n' "${dir:-none}"
    printf 'drm fingerprint: %s\n' "$(drm_fingerprint)"
    printf 'watch pid:       %s\n' "$pid"
    printf 'switch identity: %s\n' "$(switch_port_identity || echo none)"
    printf 'detected single: %s\n' "$(detect_single_profile || echo none)"
}

usage() {
    echo "Usage: display-switch.sh [restore|single|desk|watch|status|detect|<profile>]"
}

main() {
    load_host_conf
    case "${1:-restore}" in
        restore|apply) cmd_restore ;;
        single|hdmi) cmd_single ;;
        desk) cmd_desk ;;
        watch) cmd_watch ;;
        start-watch) start_watch ;;
        stop-watch|stop) stop_watch ;;
        restore-watch) start_watch ;;
        status) cmd_status ;;
        detect) detect_single_profile ;;
        -h|--help|help) usage ;;
        *) cmd_set "$1" ;;
    esac
}

main "$@"
