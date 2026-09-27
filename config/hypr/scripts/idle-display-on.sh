#!/usr/bin/env bash
# Wake outputs after idle. Do not re-run the full profile apply here;
# that path rewrites every monitor and can fight HDMI disable/enable.

PROFILE="${HOME}/.config/hypr/scripts/display-profile.sh"

WALLPAPER="${HOME}/.config/hypr/scripts/astro-wallpaper.sh"

hyprctl dispatch dpms on

if [ -x "$PROFILE" ]; then
    "$PROFILE" idle-on
else
    echo "display-profile.sh missing; falling back to dpms on" >&2
fi

# The 06:30 refresh only writes stills for outputs that are enabled then.
# Re-apply after wake so a monitor idle had disabled gets one. apply
# no-ops when the conf already matches.
if [ -x "$WALLPAPER" ]; then
    "$WALLPAPER" apply || true
fi
