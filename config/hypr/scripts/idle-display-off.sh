#!/usr/bin/env bash
# Blank outputs through the host/profile script so new machines do not need
# another HDMI special case here.

PROFILE="${HOME}/.config/hypr/scripts/display-profile.sh"

if [ -x "$PROFILE" ]; then
    "$PROFILE" idle-off
else
    echo "display-profile.sh missing; falling back to dpms off" >&2
    hyprctl dispatch dpms off
fi
