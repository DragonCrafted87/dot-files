#!/usr/bin/env bash
# Desk chrome switch. quickshell is the logged-in session.
# hyprtoolkit opens hyprlauncher, which follows hyprtoolkit.conf.

set -euo pipefail

usage() {
    printf 'Usage: %s status|toggle\n' "$(basename "$0")"
}

shell_file() {
    if [[ -n "${DESK_SHELL_FILE:-}" ]]; then
        printf '%s\n' "$DESK_SHELL_FILE"
        return 0
    fi
    printf '%s\n' "${HOME}/.config/hypr/conf.d/shell.conf"
}

desk_shell() {
    local file value
    file="$(shell_file)"
    value="quickshell"
    if [[ -f "$file" ]]; then
        value="$(
            grep -E '^DESK_SHELL=' "$file" | tail -n 1 | cut -d= -f2- | tr -d '[:space:]' || true
        )"
    fi
    case "$value" in
        hyprtoolkit | quickshell) ;;
        *) value="quickshell" ;;
    esac
    printf '%s\n' "$value"
}

main() {
    local cmd="${1:-}"
    case "$cmd" in
        status)
            desk_shell
            ;;
        toggle)
            if [[ "$(desk_shell)" == "hyprtoolkit" ]]; then
                exec hyprlauncher --toggle
            fi
            exec qs -c startmenu ipc call startmenu toggle
            ;;
        *)
            usage >&2
            exit 1
            ;;
    esac
}

main "$@"
