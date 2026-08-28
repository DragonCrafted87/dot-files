#!/bin/sh

# Re-enable with an explicit mode if you know it — more reliable than preferred,auto,1
# Example: hyprctl keyword monitor "HDMI-A-1,2560x1440@144,0x0,1"
hyprctl keyword monitor "HDMI-A-1,2560x1440@143.91Hz,6000x0,1"

sleep 0.6

hyprctl dispatch dpms on

# workspace 3 belongs on HDMI
hyprctl dispatch moveworkspacetomonitor 3 HDMI-A-1
hyprctl dispatch focusmonitor HDMI-A-1
hyprctl dispatch workspace 3

# Recreate cursor after the modeset
hyprctl dispatch movecursor 1 1
