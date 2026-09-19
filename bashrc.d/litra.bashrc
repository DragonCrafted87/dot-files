#!/usr/bin/env bash
# Console helpers for the desk Litra Glow pair.
# Manual on/toggle sets a hold so the camera watcher will not turn the
# lamps off. Camera start still forces them on. `litra-off` clears hold.

_litra_py() {
    local script="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/litra-camera-lights.py"
    if [[ ! -f "$script" ]]; then
        printf 'missing %s\n' "$script" >&2
        return 1
    fi
    python3 "$script" "$@"
}

litra-on() { _litra_py on; }
litra-off() { _litra_py off; }
litra-toggle() { _litra_py toggle; }
litra-status() { _litra_py status; }
