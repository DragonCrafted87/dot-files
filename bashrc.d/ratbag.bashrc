#!/usr/bin/env bash
# Console helpers for Logitech ratbag profile reset (G603/G604).

_reset_ratbag_profile() {
    local script="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/reset-ratbag-profile.sh"
    if [[ ! -x "$script" && ! -f "$script" ]]; then
        printf 'missing %s\n' "$script" >&2
        return 1
    fi
    "$script" "$@"
}

reset-ratbag-profile() { _reset_ratbag_profile "${1:-apply}"; }
ratbag-status() { _reset_ratbag_profile status; }
