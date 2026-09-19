#!/usr/bin/env bash
# Create ~/.local/state/hypr/monitors.runtime.conf if Hyprland would
# otherwise fail to source it. Safe to run from display-switch, role,
# or a login shell.
set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
RUNTIME="${STATE_DIR}/monitors.runtime.conf"
SEED="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/conf.d/monitors.d/default.conf"
CREATED=0

mkdir -p "$STATE_DIR"
if [[ ! -f "$RUNTIME" ]]; then
    if [[ -f "$SEED" ]]; then
        cat "$SEED" >"$RUNTIME"
    else
        printf 'monitor=,highrr,auto,1\n' >"$RUNTIME"
    fi
    CREATED=1
fi

if [[ "$CREATED" -eq 1 ]] && command -v hyprctl >/dev/null 2>&1; then
    if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || pgrep -x Hyprland >/dev/null 2>&1; then
        hyprctl reload >/dev/null 2>&1 || true
    fi
fi
