#!/usr/bin/env bash
# HDMI-switch helper for hosts with SINGLE_PROFILES in hosts.d/<host>.conf.
# Detects the panel on SWITCH_PORT and runs display-profile.sh <profile>.
set -euo pipefail

HOST="$(hostname -s 2>/dev/null || hostname)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_SH="${SCRIPT_DIR}/display-profile.sh"
MONITORS_D="${SCRIPT_DIR}/../conf.d/monitors.d"
HOSTS_D="${SCRIPT_DIR}/../conf.d/hosts.d"
AUDIO_SH="${SCRIPT_DIR}/display-audio.sh"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
PROFILE_FILE="${STATE_DIR}/display-profile"

IDLE_MONITOR=""
DESK_PORTS=""
SWITCH_PORT=""
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
            SINGLE_PROFILES) SINGLE_PROFILES="$val" ;;
            DEFAULT_SINGLE_PROFILE) DEFAULT_SINGLE_PROFILE="$val" ;;
        esac
    done <"$file"
}

current_profile() {
    if [[ -f "$PROFILE_FILE" ]]; then tr -d '[:space:]' <"$PROFILE_FILE"; else echo ""; fi
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

apply_detected() {
    local profile="${1:-}"
    [[ -n "$profile" ]] || return 1
    "$PROFILE_SH" "$profile"
    if [[ -x "$AUDIO_SH" ]]; then
        "$AUDIO_SH" "$profile" || true
    fi
}

cmd_single() {
    local profile
    profile="$(detect_single_profile || true)"
    profile="${profile:-$DEFAULT_SINGLE_PROFILE}"
    if [[ -z "$profile" ]]; then
        echo "display-switch: no HDMI panel matched on ${HOST}" >&2
        return 1
    fi
    apply_detected "$profile"
}

cmd_watch() {
    local last_id="" id current detected
    last_id="$(switch_port_identity || echo none)"
    while true; do
        current="$(current_profile)"
        id="$(switch_port_identity || echo none)"
        if is_single_profile "$current"; then
            detected="$(detect_single_profile || true)"
            if [[ -n "$detected" ]]; then
                if [[ "$detected" != "$current" ]]; then
                    apply_detected "$detected" || true
                elif [[ "$last_id" == none && "$id" != none ]]; then
                    apply_detected "$detected" || true
                fi
            fi
        fi
        last_id="$id"
        sleep 1
    done
}

cmd_status() {
    printf 'host:            %s\n' "$HOST"
    printf 'saved profile:   %s\n' "$(current_profile)"
    printf 'switch port:     %s\n' "${SWITCH_PORT:-none}"
    printf 'switch identity: %s\n' "$(switch_port_identity || echo none)"
    printf 'detected single: %s\n' "$(detect_single_profile || echo none)"
}

usage() { echo "Usage: display-switch.sh [single|watch|status|detect]"; }

main() {
    load_host_conf
    case "${1:-single}" in
        single|hdmi|"") cmd_single ;;
        watch) cmd_watch ;;
        status) cmd_status ;;
        detect) detect_single_profile ;;
        -h|--help|help) usage ;;
        *) usage >&2; return 2 ;;
    esac
}

main "$@"
