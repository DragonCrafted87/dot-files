#!/usr/bin/env bash
# Console helpers for Piper/ratbag profile reset (Logitech G603).

_reset_piper_profile() {
    local script="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/reset-piper-profile.sh"
    if [[ ! -x "$script" && ! -f "$script" ]]; then
        printf 'missing %s\n' "$script" >&2
        return 1
    fi
    "$script" "$@"
}

reset-piper-profile() { _reset_piper_profile "${1:-apply}"; }
piper-g603-status() { _reset_piper_profile status; }
