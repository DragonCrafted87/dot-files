#!/usr/bin/env bash
# Audio half of display-profile. Sourced from display-profile.sh or run
# alone: display-audio.sh theater|desk|workshare|stereo|status
set -euo pipefail

HOST="${HOST:-$(hostname -s 2>/dev/null || hostname)}"
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
AUDIO_D="${AUDIO_D:-${SCRIPT_DIR}/../conf.d/audio.d}"
STATE_DIR="${STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}"
PROFILE_FILE="${PROFILE_FILE:-${STATE_DIR}/display-profile}"
SAVED_SINK_FILE="${SAVED_SINK_FILE:-${STATE_DIR}/desk-audio-sink}"
THEATER_SINK_MATCH="${THEATER_SINK_MATCH:-hdmi-surround71-extra3}"
DESK_SINK_MATCH="${DESK_SINK_MATCH:-pci-0000_18_00.6.iec958-stereo}"
SINK_MATCH=""
SINK_FALLBACK=""
CARD=""
CARD_PROFILE=""
CARD_PROFILE_FALLBACK=""

audio_notify() {
    local msg="$1" color="${2:-rgb(305cde)}"
    printf '%s\n' "$msg"
    if command -v hyprctl >/dev/null 2>&1; then
        hyprctl notify -1 4000 "$color" "$msg" >/dev/null 2>&1 || true
    fi
}

list_sinks() { command -v pactl >/dev/null 2>&1 && pactl list short sinks 2>/dev/null | awk '{print $2}'; }
default_sink() { command -v pactl >/dev/null 2>&1 && pactl get-default-sink 2>/dev/null || true; }

find_sink() {
    local match="$1"
    [[ -n "$match" ]] || return 1
    list_sinks | awk -v m="$match" 'BEGIN{IGNORECASE=1} $0 ~ m {print; exit}'
}

card_has_profile() {
    local card="$1" profile="$2"
    [[ -n "$card" && -n "$profile" ]] || return 1
    pactl list cards 2>/dev/null | awk -v card="$card" -v want="$profile" '
        $1=="Name:" && $2==card {in_card=1; next}
        in_card && $1=="Name:" {exit}
        in_card && $0 ~ "output:" want {found=1}
        END {exit found?0:1}
    '
}

load_audio_conf() {
    local profile="$1" file
    SINK_MATCH=""
    SINK_FALLBACK=""
    CARD=""
    CARD_PROFILE=""
    CARD_PROFILE_FALLBACK=""
    file="${AUDIO_D}/${HOST}-${profile}.conf"
    [[ -f "$file" ]] || return 0
    # shellcheck disable=SC1090
    . "$file"
}

set_card_profile() {
    local card="$1" profile="$2"
    [[ -n "$card" && -n "$profile" ]] || return 1
    pactl set-card-profile "$card" "output:${profile}" >/dev/null 2>&1 || \
        pactl set-card-profile "$card" "$profile" >/dev/null 2>&1
}

ensure_card_profile() {
    local card="${CARD:-}" preferred="${CARD_PROFILE:-}" fallback="${CARD_PROFILE_FALLBACK:-}"
    command -v pactl >/dev/null 2>&1 || return 0
    [[ -n "$card" ]] || return 0
    if [[ -n "$preferred" ]] && card_has_profile "$card" "$preferred"; then
        set_card_profile "$card" "$preferred" && return 0
    fi
    if [[ -n "$fallback" ]] && card_has_profile "$card" "$fallback"; then
        audio_notify "Theater audio: ${preferred:-7.1} missing, using ${fallback}" "rgb(de9f30)"
        set_card_profile "$card" "$fallback" && return 0
    fi
    return 1
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
    audio_notify "Audio → ${sink}"
}

current_display_profile() {
    if [[ -f "$PROFILE_FILE" ]]; then
        tr -d '[:space:]' <"$PROFILE_FILE"
    else
        echo ""
    fi
}

apply_audio_profile() {
    local profile="$1" sink="" tries=0
    load_audio_conf "$profile"
    case "$profile" in
        theater)
            SINK_MATCH="${SINK_MATCH:-$THEATER_SINK_MATCH}"
            SINK_FALLBACK="${SINK_FALLBACK:-hdmi-stereo-extra3}"
            CARD="${CARD:-alsa_card.pci-0000_03_00.1}"
            CARD_PROFILE="${CARD_PROFILE:-hdmi-surround71-extra3}"
            CARD_PROFILE_FALLBACK="${CARD_PROFILE_FALLBACK:-hdmi-stereo-extra3}"
            ;;
        desk | workshare)
            SINK_MATCH="${SINK_MATCH:-$DESK_SINK_MATCH}"
            ;;
        stereo)
            CARD="${CARD:-alsa_card.pci-0000_03_00.1}"
            CARD_PROFILE="hdmi-stereo-extra3"
            SINK_MATCH="hdmi-stereo-extra3"
            SINK_FALLBACK="hdmi-stereo-extra3"
            ;;
    esac
    command -v pactl >/dev/null 2>&1 || {
        audio_notify "pactl missing; audio not switched" "rgb(de3030)"
        return 1
    }
    if [[ "$profile" == theater || "$profile" == stereo ]]; then
        ensure_card_profile || true
        while ((tries < 8)); do
            sink="$(find_sink "$SINK_MATCH" || true)"
            [[ -n "$sink" ]] && break
            sink="$(find_sink "$SINK_FALLBACK" || true)"
            [[ -n "$sink" ]] && break
            sleep 0.5
            tries=$((tries + 1))
            ensure_card_profile || true
        done
    else
        sink="$(find_sink "$SINK_MATCH" || true)"
    fi
    if [[ -z "$sink" ]]; then
        audio_notify "Audio failed (no sink for ${SINK_MATCH:-?} / ${SINK_FALLBACK:-none})" "rgb(de3030)"
        return 1
    fi
    if [[ "$profile" == theater && "$sink" != *surround71* ]]; then
        audio_notify "HDMI 7.1 not live; using stereo. Reboot if you need 7.1." "rgb(de9f30)"
    fi
    set_sink "$sink"
}

restore_profile_audio() {
    local profile
    profile="${1:-$(current_display_profile)}"
    [[ -n "$profile" ]] || profile=desk
    apply_audio_profile "$profile"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    cmd="${1:-status}"
    case "$cmd" in
        status)
            printf 'profile: %s\n' "$(current_display_profile)"
            printf 'default: %s\n' "$(default_sink)"
            list_sinks | sed 's/^/  /'
            ;;
        theater | desk | workshare | stereo) apply_audio_profile "$cmd" ;;
        restore) restore_profile_audio "${2:-}" ;;
        *) echo "Usage: display-audio.sh [status|theater|desk|workshare|stereo|restore]" >&2; exit 2 ;;
    esac
fi
