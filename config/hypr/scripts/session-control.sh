#!/usr/bin/env bash
# Session actions for the start menu and keybinds.
# Prefer hyprshutdown so clients get a graceful close instead of dispatch exit.
set -euo pipefail

usage() {
    echo "Usage: session-control.sh lock|logout|suspend|reboot|shutdown" >&2
    exit 1
}

have() { command -v "$1" >/dev/null 2>&1; }

graceful() {
    local title="$1"
    local post="${2:-}"
    if have hyprshutdown; then
        if [[ -n "$post" ]]; then
            exec hyprshutdown -t "$title" --post-cmd "$post"
        fi
        exec hyprshutdown -t "$title"
    fi
    if [[ -n "$post" ]]; then
        # shellcheck disable=SC2086
        exec $post
    fi
    exec hyprctl dispatch exit
}

case "${1:-}" in
    lock)
        if have loginctl; then
            exec loginctl lock-session
        fi
        exec hyprlock
        ;;
    logout)
        graceful "Logging out..."
        ;;
    suspend)
        # hypridle before_sleep_cmd already locks the session.
        exec systemctl suspend
        ;;
    reboot)
        graceful "Restarting..." "systemctl reboot"
        ;;
    shutdown|poweroff)
        graceful "Shutting down..." "systemctl poweroff"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage
        ;;
esac
