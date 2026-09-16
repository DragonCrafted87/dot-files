#!/usr/bin/env bash
# Audio half of display-profile. Sourced from display-profile.sh or run
# alone: display-audio.sh theater|desk|status
set -euo pipefail

HOST="${HOST:-$(hostname -s 2>/dev/null || hostname)}"
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
AUDIO_D="${AUDIO_D:-${SCRIPT_DIR}/../conf.d/audio.d}"
STATE_DIR="${STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}"
SAVED_SINK_FILE="${SAVED_SINK_FILE:-${STATE_DIR}/desk-audio-sink}"
THEATER_SINK_MATCH="${THEATER_SINK_MATCH:-hdmi-surround71}"
DESK_SINK_MATCH="${DESK_SINK_MATCH:-Jabra_Speak_710}"
SINK_MATCH=""
CARD_PROFILE=""

list_sinks() { command -v pactl >/dev/null 2>&1 && pactl list short sinks 2>/dev/null | awk '{print $2}'; }
default_sink() { command -v pactl >/dev/null 2>&1 && pactl get-default-sink 2>/dev/null || true; }

find_sink() {
    local match="$1"
    [[ -n "$match" ]] || return 1
    list_sinks | awk -v m="$match" 'BEGIN{IGNORECASE=1} $0 ~ m {print; exit}'
}

load_audio_conf() {
    local profile="$1" file
    SINK_MATCH=""
    CARD_PROFILE=""
    file="${AUDIO_D}/${HOST}-${profile}.conf"
    [[ -f "$file" ]] || return 0
    # shellcheck disable=SC1090
    . "$file"
}

ensure_card_profile() {
    local sink_hint="${1:-}" profile_name="${2:-}" card rest
    [[ -n "$profile_name" ]] || return 0
    command -v pactl >/dev/null 2>&1 || return 0
    if [[ -n "$sink_hint" && "$sink_hint" == alsa_output.* ]]; then
        rest="${sink_hint#alsa_output.}"
        card="alsa_card.${rest%.*}"
        pactl set-card-profile "$card" "output:${profile_name}" >/dev/null 2>&1 || \
            pactl set-card-profile "$card" "$profile_name" >/dev/null 2>&1 || true
        return 0
    fi
    while read -r card; do
        [[ -n "$card" ]] || continue
        pactl set-card-profile "$card" "output:${profile_name}" >/dev/null 2>&1 && break
    done < <(pactl list short cards 2>/dev/null | awk '{print $2}')
}

move_all_streams() {
    local sink="$1" id
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
    printf 'Audio → %s\n' "$sink"
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

apply_audio_profile() {
    local profile="$1" match sink
    load_audio_conf "$profile"
    case "$profile" in
        theater) match="${SINK_MATCH:-$THEATER_SINK_MATCH}" ;;
        desk | workshare) match="${SINK_MATCH:-$DESK_SINK_MATCH}" ;;
        *) match="${SINK_MATCH:-}" ;;
    esac
    [[ -n "$match" ]] || return 0
    command -v pactl >/dev/null 2>&1 || return 0
    if [[ "$profile" == theater ]]; then
        save_current_sink
        ensure_card_profile "$(find_sink "$match" || true)" "${CARD_PROFILE:-hdmi-surround71}"
        sleep 0.4
    fi
    sink="$(find_sink "$match" || true)"
    if [[ -z "$sink" ]]; then
        printf 'No sink matched %s\n' "$match" >&2
        list_sinks | sed 's/^/  /' >&2 || true
        return 1
    fi
    set_sink "$sink"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    cmd="${1:-status}"
    case "$cmd" in
        status)
            printf 'default: %s\n' "$(default_sink)"
            list_sinks | sed 's/^/  /'
            ;;
        theater | desk | workshare) apply_audio_profile "$cmd" ;;
        *) echo "Usage: display-audio.sh [status|theater|desk|workshare]" >&2; exit 2 ;;
    esac
fi
