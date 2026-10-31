#!/usr/bin/env bash
# While the session is awake, a panel power-on leaves Hyprland with the
# output enabled and DPMS off. hypridle does not run idle-display-on again.
# Watch DRM status for the idle output and the desk ports, and ask
# display-profile.sh to turn DPMS back on. idle-blanked blocks that during
# a real idle blank, because HDMI must not wake itself.
set -euo pipefail

PATH="/usr/local/bin:${PATH:-/usr/bin:/bin}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOSTS_D="${SCRIPT_DIR}/../conf.d/hosts.d"
PROFILE_SH="${SCRIPT_DIR}/display-profile.sh"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
BLANKED_FILE="${STATE_DIR}/idle-blanked"
PID_FILE="${STATE_DIR}/idle-display-watch.pid"
HOST="$(hostname -s 2>/dev/null || hostname)"
IDLE_MONITOR=""
DESK_PORTS=""

usage() {
    echo "Usage: idle-display-watch.sh [ensure|watch|stop|status|help]" >&2
}

load_host_conf() {
    local file="${HOSTS_D}/${HOST}.conf" line key val
    IDLE_MONITOR=""
    DESK_PORTS=""
    [[ -f "$file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -n "$line" && "$line" == *=* ]] || continue
        key="${line%%=*}"
        val="${line#*=}"
        key="${key%"${key##*[![:space:]]}"}"
        val="${val#"${val%%[![:space:]]*}"}"
        case "$key" in
            IDLE_MONITOR) IDLE_MONITOR="$val" ;;
            DESK_PORTS) DESK_PORTS="$val" ;;
        esac
    done <"$file"
}

idle_reconnect_should_wake() {
    local status="$1"
    [[ "$status" == "connected" ]] || return 1
    [[ -f "$BLANKED_FILE" ]] && return 1
    return 0
}

drm_status_files_for() {
    local port d root="${IDLE_WATCH_DRM_ROOT:-/sys/class/drm}"
    shopt -s nullglob
    for port in "$@"; do
        [[ -n "$port" ]] || continue
        for d in "$root"/card*-"$port"; do
            [[ -e "$d/status" ]] || continue
            printf '%s\n' "$d/status"
        done
    done
    shopt -u nullglob
}

wake_ports() {
    local port seen=" "
    if [[ -n "$IDLE_MONITOR" ]]; then
        printf '%s\n' "$IDLE_MONITOR"
        seen+="$IDLE_MONITOR "
    fi
    # shellcheck disable=SC2086
    for port in $DESK_PORTS; do
        [[ -n "$port" ]] || continue
        [[ "$seen" == *" $port "* ]] && continue
        seen+="$port "
        printf '%s\n' "$port"
    done
}

status_files() {
    local port
    local -a ports=()
    while IFS= read -r port; do
        [[ -n "$port" ]] || continue
        ports+=("$port")
    done < <(wake_ports)
    ((${#ports[@]} > 0)) || return 0
    drm_status_files_for "${ports[@]}"
}

port_from_status() {
    local dir
    dir="$(basename "$(dirname "$1")")"
    printf '%s\n' "${dir#card*-}"
}

on_status_file() {
    local file="$1" status port
    [[ -e "$file" ]] || return 0
    status="$(tr -d '[:space:]' <"$file" 2>/dev/null || true)"
    idle_reconnect_should_wake "$status" || return 0
    port="$(port_from_status "$file")"
    [[ -n "$port" ]] || return 0
    [[ -x "$PROFILE_SH" ]] || return 0
    "$PROFILE_SH" wake-dpms "$port" || true
}

watch_pid() {
    [[ -f "$PID_FILE" ]] || return 1
    tr -d '[:space:]' <"$PID_FILE"
}

watch_running() {
    local pid
    pid="$(watch_pid || true)"
    [[ -n "$pid" ]] || return 1
    kill -0 "$pid" 2>/dev/null
}

cmd_stop() {
    local pid
    pid="$(watch_pid || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill -- "-${pid}" 2>/dev/null || kill "$pid" 2>/dev/null || true
        pkill -P "$pid" >/dev/null 2>&1 || true
    fi
    rm -f "$PID_FILE"
}

cmd_watch() {
    local -a files=() targets=()
    local file event dir
    load_host_conf
    while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        files+=("$file")
        targets+=("$file")
        dir="$(dirname "$file")"
        targets+=("$dir")
    done < <(status_files)
    if ((${#files[@]} == 0)); then
        echo "idle-display-watch: no DRM status files for this host" >&2
        return 0
    fi
    if ! command -v inotifywait >/dev/null 2>&1; then
        echo "idle-display-watch: inotifywait missing; install inotify-tools" >&2
        return 1
    fi
    while true; do
        event="$(inotifywait -q -e modify,attrib,close_write --format '%w%f' -- "${targets[@]}" 2>/dev/null || true)"
        sleep 0.4
        if [[ -n "$event" && -f "$event" && "$(basename "$event")" == "status" ]]; then
            on_status_file "$event"
        else
            for file in "${files[@]}"; do
                on_status_file "$file"
            done
        fi
    done
}

cmd_ensure() {
    if watch_running; then
        return 0
    fi
    if ! command -v inotifywait >/dev/null 2>&1; then
        echo "idle-display-watch: inotifywait missing; install inotify-tools" >&2
        return 1
    fi
    mkdir -p "$STATE_DIR"
    setsid "$0" watch </dev/null >/dev/null 2>&1 &
    echo $! >"$PID_FILE"
}

cmd_status() {
    local pid
    if watch_running; then
        pid="$(watch_pid)"
        printf 'idle-display-watch: running %s\n' "$pid"
        return 0
    fi
    printf 'idle-display-watch: stopped\n'
    return 1
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    cmd="${1:-ensure}"
    case "$cmd" in
        ensure) cmd_ensure ;;
        watch) cmd_watch ;;
        stop) cmd_stop ;;
        status) cmd_status ;;
        -h | --help | help) usage ;;
        *)
            usage
            exit 1
            ;;
    esac
fi
