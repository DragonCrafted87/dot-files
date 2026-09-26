#!/usr/bin/env bash
# Start desk GUI apps after graphical-session.target is bound.
# Hyprland exec-once no longer launches these; this unit does.
set -euo pipefail

CONFIG_HYPR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
DISCORD_BIN="/var/lib/flatpak/app/com.discordapp.Discord/current/active/export/bin/com.discordapp.Discord"

usage() {
    echo "Usage: workstation-session.sh start|status|help" >&2
}

log() {
    printf 'workstation-session: %s\n' "$*"
}

running() {
    local needle="$1"
    pgrep -u "$(id -u)" -f "$needle" >/dev/null 2>&1
}

running_name() {
    local name="$1"
    pgrep -u "$(id -u)" -x "$name" >/dev/null 2>&1
}

hypr_exec() {
    local cmd="$1"
    if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || ! command -v hyprctl >/dev/null 2>&1; then
        log "no hyprctl; skip ${cmd}"
        return 0
    fi
    hyprctl dispatch exec "$cmd"
}

start_one() {
    local needle="$1"
    local cmd="$2"
    if running "$needle"; then
        log "already ${needle}"
        return 0
    fi
    log "start ${cmd}"
    hypr_exec "$cmd"
}

start_named() {
    local name="$1"
    local cmd="$2"
    if running_name "$name"; then
        log "already ${name}"
        return 0
    fi
    log "start ${cmd}"
    hypr_exec "$cmd"
}

cmd_start() {
    start_named kitty kitty
    # Wrapper is brave-browser; the process comm is brave.
    start_named brave brave-browser
    start_named steam steam
    if [[ -x "$DISCORD_BIN" ]]; then
        start_one 'com.discordapp.Discord' "$DISCORD_BIN"
    fi
    start_one 'kdeconnect-indicator|kdeconnectd' "bash ${CONFIG_HYPR}/scripts/start-kdeconnect.sh"
    start_one 'qs -c startmenu' "${CONFIG_HYPR}/scripts/startmenu.sh"
    start_one 'spin-border.sh' "${CONFIG_HYPR}/scripts/spin-border.sh"
    start_one 'litra-camera-lights.py' "python3 ${CONFIG_HYPR}/scripts/litra-camera-lights.py watch"
}

cmd_status() {
    if running_name kitty; then
        printf 'kitty running\n'
    else
        printf 'kitty missing\n'
    fi
    if running_name brave; then
        printf 'brave running\n'
    else
        printf 'brave missing\n'
    fi
    if running_name steam; then
        printf 'steam running\n'
    else
        printf 'steam missing\n'
    fi
    if running 'com.discordapp.Discord'; then
        printf 'discord running\n'
    else
        printf 'discord missing\n'
    fi
    if running 'kdeconnect-indicator|kdeconnectd'; then
        printf 'kdeconnect running\n'
    else
        printf 'kdeconnect missing\n'
    fi
    if running 'qs -c startmenu'; then
        printf 'startmenu running\n'
    else
        printf 'startmenu missing\n'
    fi
    if running 'spin-border.sh'; then
        printf 'spin-border running\n'
    else
        printf 'spin-border missing\n'
    fi
    if running 'litra-camera-lights.py'; then
        printf 'litra running\n'
    else
        printf 'litra missing\n'
    fi
}

main() {
    case "${1:-start}" in
        start) cmd_start ;;
        status) cmd_status ;;
        -h | --help | help) usage ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"
