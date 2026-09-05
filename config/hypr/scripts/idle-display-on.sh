#!/bin/sh
# Wake outputs after idle. Do not re-run the full profile apply here;
# that path rewrites every monitor and can fight HDMI disable/enable.

PROFILE="${HOME}/.config/hypr/scripts/display-profile.sh"

hyprctl dispatch dpms on

if [ -x "$PROFILE" ]; then
    "$PROFILE" idle-on
else
    echo "display-profile.sh missing; falling back to dpms on" >&2
fi
