#!/bin/sh
# Wake outputs by re-applying the saved host/profile layout.
# HDMI can take several seconds after DPMS/disable before Hyprland will
# accept workspace moves, so give the panel a moment before apply.

PROFILE="${HOME}/.config/hypr/scripts/display-profile.sh"

hyprctl dispatch dpms on

sleep 2

if [ -x "$PROFILE" ]; then
    "$PROFILE" apply
else
    echo "display-profile.sh missing; falling back to dpms on" >&2
fi

hyprctl dispatch movecursor 1 1
