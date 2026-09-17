#!/usr/bin/env bash
# Steam launch wrapper. Reads the active Hyprland display profile and
# points Proton at the largest enabled output, or spans all enabled
# outputs when SPAN=1 and more than one panel is live.
#
# Steam Launch Options:
#   ~/.config/hypr/scripts/steam-proton-wrap.sh %command%
set -euo pipefail

HOST="$(hostname -s 2>/dev/null || hostname)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITORS_D="${SCRIPT_DIR}/../conf.d/monitors.d"
GAMES_D="${SCRIPT_DIR}/../steam-games"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
PROFILE_FILE="${STATE_DIR}/display-profile"
WRAP_LOG="${STATE_DIR}/steam-wrap.log"
AUDIO_SH="${SCRIPT_DIR}/display-audio.sh"

trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s\n' "$s"
}

wrap_log() {
    mkdir -p "$STATE_DIR" 2>/dev/null || true
    printf '%s %s\n' "$(date -Iseconds 2>/dev/null || date)" "$*" >>"$WRAP_LOG" 2>/dev/null || true
}

current_profile() {
    if [[ -f "$PROFILE_FILE" ]]; then
        trim "$(tr -d '\r' <"$PROFILE_FILE")"
    else
        echo ""
    fi
}

restore_profile_audio() {
    [[ "${GAME_AUDIO:-}" == "stereo" ]] || return 0
    [[ -x "$AUDIO_SH" ]] || return 0
    "$AUDIO_SH" restore "$(current_profile)" >/dev/null 2>&1 || true
    wrap_log "audio restored $(current_profile)"
}

apply_game_audio() {
    [[ "${GAME_AUDIO:-}" == "stereo" ]] || return 0
    [[ -x "$AUDIO_SH" ]] || return 0
    wrap_log "audio stereo for game"
    "$AUDIO_SH" stereo || true
}

profile_conf() {
    local profile="${1:-}" file
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

monitor_lines() {
    local file="$1" line spec
    [[ -f "$file" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="$(trim "$line")"
        [[ -n "$line" ]] || continue
        [[ "$line" == monitor* ]] || continue
        spec="${line#monitor}"
        spec="${spec#"${spec%%[![:space:]=]*}"}"
        spec="${spec#=}"
        spec="$(trim "$spec")"
        [[ -n "$spec" ]] || continue
        printf '%s\n' "$spec"
    done <"$file"
}

monitor_name() { printf '%s\n' "${1%%,*}"; }
monitor_is_disabled() { [[ "${1#*,}" == disable ]]; }

mode_pixels() {
    local spec="$1" rest mode w h
    rest="${spec#*,}"
    mode="${rest%%,*}"
    mode="${mode%%@*}"
    w="${mode%%x*}"
    h="${mode#*x}"
    if [[ "$w" =~ ^[0-9]+$ && "$h" =~ ^[0-9]+$ ]]; then
        printf '%s %s %s\n' "$w" "$h" "$((w * h))"
        return 0
    fi
    return 1
}

live_monitor_json() {
    command -v hyprctl >/dev/null 2>&1 || return 1
    hyprctl monitors -j 2>/dev/null || return 1
}

live_monitor_info() {
    local mon="$1" json
    json="$(live_monitor_json)" || return 1
    printf '%s\n' "$json" | python3 -c '
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
    w = int(m.get("width") or 0)
    h = int(m.get("height") or 0)
    x = int(m.get("x") or 0)
    y = int(m.get("y") or 0)
    focused = 1 if m.get("focused") else 0
    if w <= 0 or h <= 0:
        raise SystemExit(1)
    print(f"{w} {h} {focused} {x} {y}")
    raise SystemExit(0)
raise SystemExit(1)
' "$mon" 2>/dev/null
}

enabled_names() {
    local file="$1" spec name
    while IFS= read -r spec; do
        [[ -n "$spec" ]] || continue
        monitor_is_disabled "$spec" && continue
        name="$(monitor_name "$spec")"
        [[ -n "$name" ]] || continue
        printf '%s\n' "$name"
    done < <(monitor_lines "$file")
}

pick_largest() {
    local file="$1" spec name best_name="" best_area=0 w h area info
    while IFS= read -r spec; do
        [[ -n "$spec" ]] || continue
        monitor_is_disabled "$spec" && continue
        name="$(monitor_name "$spec")"
        [[ -n "$name" ]] || continue
        if info="$(live_monitor_info "$name" || true)" && [[ -n "$info" ]]; then
            w="${info%% *}"
            h="$(echo "$info" | awk '{print $2}')"
            area=$((w * h))
        elif mode_pixels "$spec" >/dev/null; then
            read -r w h area < <(mode_pixels "$spec")
        else
            area=0
        fi
        if ((area >= best_area)); then
            best_area=$area
            best_name="$name"
        fi
    done < <(monitor_lines "$file")
    [[ -n "$best_name" ]] || return 1
    printf '%s\n' "$best_name"
}

span_box() {
    local file="$1" name info w h x y
    local minx=999999 miny=999999 maxx=-999999 maxy=-999999 count=0
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        info="$(live_monitor_info "$name" || true)"
        [[ -n "$info" ]] || continue
        w="$(echo "$info" | awk '{print $1}')"
        h="$(echo "$info" | awk '{print $2}')"
        x="$(echo "$info" | awk '{print $4}')"
        y="$(echo "$info" | awk '{print $5}')"
        count=$((count + 1))
        if ((x < minx)); then minx=$x; fi
        if ((y < miny)); then miny=$y; fi
        if ((x + w > maxx)); then maxx=$((x + w)); fi
        if ((y + h > maxy)); then maxy=$((y + h)); fi
    done < <(enabled_names "$file")
    if ((count >= 2 && maxx > minx && maxy > miny)); then
        printf '%s %s %s\n' "$((maxx - minx))" "$((maxy - miny))" "$count"
        return 0
    fi
    return 1
}

resolve_output() {
    local file profile want
    profile="$(current_profile)"
    file="$(profile_conf "$profile" || true)"
    want="${STEAM_GAME_OUTPUT:-}"
    if [[ -n "$want" ]]; then
        printf '%s\n' "$want"
        return 0
    fi
    if [[ -n "$file" ]]; then
        pick_largest "$file" && return 0
    fi
    return 1
}

resolve_size() {
    local mon="$1" info w h
    if info="$(live_monitor_info "$mon" || true)" && [[ -n "$info" ]]; then
        w="${info%% *}"
        h="$(echo "$info" | awk '{print $2}')"
        printf '%s %s\n' "$w" "$h"
        return 0
    fi
    return 1
}

app_id() {
    local id
    for id in "${SteamAppId:-}" "${SteamGameId:-}" "${STEAM_COMPAT_APP_ID:-}"; do
        [[ -n "$id" && "$id" != "0" ]] && { printf '%s\n' "$id"; return 0; }
    done
    return 1
}

load_overlay_file() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    # shellcheck disable=SC1090
    . "$file"
}

load_game_overlay() {
    local id family
    id="$(app_id || true)"
    [[ -n "$id" ]] || return 0
    load_overlay_file "${GAMES_D}/${id}.conf"
    family="${FAMILY:-}"
    if [[ -n "$family" ]]; then
        load_overlay_file "${GAMES_D}/families/${family}.conf"
        load_overlay_file "${GAMES_D}/${id}.conf"
    fi
}

pin_output() {
    local mon="$1" info w h x y cx cy
    [[ -n "$mon" ]] || return 0
    [[ "${PIN_OUTPUT:-1}" == "1" ]] || return 0
    command -v hyprctl >/dev/null 2>&1 || return 0
    info="$(live_monitor_info "$mon" || true)"
    [[ -n "$info" ]] || return 0
    w="$(echo "$info" | awk '{print $1}')"
    h="$(echo "$info" | awk '{print $2}')"
    x="$(echo "$info" | awk '{print $4}')"
    y="$(echo "$info" | awk '{print $5}')"
    [[ "$w" =~ ^[0-9]+$ && "$h" =~ ^[0-9]+$ ]] || return 0
    cx=$((x + w / 2))
    cy=$((y + h / 2))
    hyprctl dispatch movecursor "$cx" "$cy" >/dev/null 2>&1 || true
}

pin_watch() {
    local mon="$1" id="$2"
    [[ -n "$mon" && -n "$id" ]] || return 0
    command -v hyprctl >/dev/null 2>&1 || return 0
    command -v python3 >/dev/null 2>&1 || return 0
    (
        local n addr
        for n in $(seq 1 40); do
            sleep 0.5
            addr="$(hyprctl clients -j 2>/dev/null | python3 -c '
import json, sys
want = sys.argv[1]
try:
    clients = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)
for c in clients:
    cls = str(c.get("class") or "")
    if cls == f"steam_app_{want}" or cls.lower().endswith(".exe"):
        print(c.get("address") or "")
        break
' "$id" 2>/dev/null || true)"
            [[ -n "$addr" ]] || continue
            hyprctl dispatch focuswindow "address:${addr}" >/dev/null 2>&1 || true
            hyprctl dispatch movewindow "mon:${mon}" >/dev/null 2>&1 || true
            wrap_log "moved ${addr} -> ${mon}"
            break
        done
    ) &
}

cmd_status() {
    local profile file mon size w h id box
    profile="$(current_profile)"
    file="$(profile_conf "$profile" || true)"
    mon="$(resolve_output || true)"
    id="$(app_id || true)"
    printf 'host:            %s\n' "$HOST"
    printf 'saved profile:   %s\n' "${profile:-none}"
    printf 'conf:            %s\n' "${file:-none}"
    printf 'game output:     %s\n' "${mon:-unresolved}"
    printf 'gamescope:       %s\n' "${GAMESCOPE:-0}"
    printf 'game audio:      %s\n' "${GAME_AUDIO:-default}"
    if [[ -n "$mon" ]] && size="$(resolve_size "$mon" || true)" && [[ -n "$size" ]]; then
        w="${size%% *}"
        h="${size#* }"
        printf 'live mode:       %sx%s\n' "$w" "$h"
    fi
    if [[ -n "$file" ]] && box="$(span_box "$file" || true)" && [[ -n "$box" ]]; then
        printf 'span box:        %sx%s (%s heads)\n' "${box%% *}" "$(echo "$box" | awk '{print $2}')" "$(echo "$box" | awk '{print $3}')"
    fi
    printf 'appid:           %s\n' "${id:-none}"
    if [[ -n "$id" && -f "${GAMES_D}/${id}.conf" ]]; then
        printf 'overlay:         %s\n' "${GAMES_D}/${id}.conf"
    fi
}

apply_proton_env() {
    local mon size file profile box
    profile="$(current_profile)"
    file="$(profile_conf "$profile" || true)"
    mon="$(resolve_output || true)"
    WRAP_MON="$mon"
    WRAP_W=""
    WRAP_H=""
    export PROTON_FORCE_LARGE_ADDRESS_AWARE="${PROTON_FORCE_LARGE_ADDRESS_AWARE:-1}"
    export PROTON_USE_WOW64="${PROTON_USE_WOW64:-1}"
    if [[ "${NO_PROTON_WAYLAND:-0}" != "1" && "${PROTON_ENABLE_WAYLAND:-1}" != "0" ]]; then
        export PROTON_ENABLE_WAYLAND=1
    fi
    if [[ "${SPAN:-0}" == "1" && -n "$file" ]] && box="$(span_box "$file" || true)" && [[ -n "$box" ]]; then
        WRAP_W="${box%% *}"
        WRAP_H="$(echo "$box" | awk '{print $2}')"
        unset WAYLANDDRV_PRIMARY_MONITOR || true
    else
        if [[ -n "$mon" ]]; then
            export WAYLANDDRV_PRIMARY_MONITOR="$mon"
            export SDL_VIDEO_FULLSCREEN_DISPLAY="$mon"
        fi
        if size="$(resolve_size "$mon" || true)" && [[ -n "$size" ]]; then
            WRAP_W="${size%% *}"
            WRAP_H="${size#* }"
        fi
        pin_output "$mon" || true
        pin_watch "$mon" "$(app_id || true)" || true
    fi
    if [[ "${INJECT_SIZE:-0}" == "1" && -n "$WRAP_W" && -n "$WRAP_H" ]]; then
        WRAP_EXTRA_ARGS+=("-w" "$WRAP_W" "-h" "$WRAP_H")
    fi
    wrap_log "profile=${profile:-none} output=${mon:-none} size=${WRAP_W:-?}x${WRAP_H:-?} app=$(app_id || echo none) wayland=${PROTON_ENABLE_WAYLAND:-} gamescope=${GAMESCOPE:-0} audio=${GAME_AUDIO:-default}"
}

usage() { echo "Usage: steam-proton-wrap.sh [status|help] [command...]"; }

main() {
    local cmd="${1:-}" rc=0
    WRAP_EXTRA_ARGS=()
    WRAP_MON=""
    WRAP_W=""
    WRAP_H=""

    case "$cmd" in
        status) load_game_overlay; cmd_status; return 0 ;;
        -h | --help | help) usage; return 0 ;;
    esac

    load_game_overlay
    apply_proton_env

    if [[ -n "${EXTRA_ARGS:-}" ]]; then
        # shellcheck disable=SC2206
        WRAP_EXTRA_ARGS+=($EXTRA_ARGS)
    fi

    if [[ "$#" -eq 0 ]]; then
        cmd_status
        return 0
    fi

    apply_game_audio
    trap restore_profile_audio EXIT

    if [[ "${GAMESCOPE:-0}" == "1" ]] && command -v gamescope >/dev/null 2>&1 && [[ -n "$WRAP_MON" && -n "$WRAP_W" && -n "$WRAP_H" ]]; then
        wrap_log "run gamescope -O ${WRAP_MON} ${WRAP_W}x${WRAP_H}: $*"
        gamescope -f -W "$WRAP_W" -H "$WRAP_H" -O "$WRAP_MON" -- "$@" "${WRAP_EXTRA_ARGS[@]}" || rc=$?
    else
        wrap_log "run: $* ${WRAP_EXTRA_ARGS[*]:-}"
        "$@" "${WRAP_EXTRA_ARGS[@]}" || rc=$?
    fi

    restore_profile_audio
    trap - EXIT
    exit "$rc"
}

main "$@"
