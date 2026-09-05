#!/bin/sh
# Wake outputs by re-applying the saved host/profile layout.
# New hostnames and profiles only need to be added to display-profile.sh.

PROFILE="${HOME}/.config/hypr/scripts/display-profile.sh"

hyprctl dispatch dpms on

sleep 0.6

if [ -x "$PROFILE" ]; then
    "$PROFILE" apply
else
    echo "display-profile.sh missing; falling back to dpms on" >&2
fi

hyprctl dispatch movecursor 1 1
