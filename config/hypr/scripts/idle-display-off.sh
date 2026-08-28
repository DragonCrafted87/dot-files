#!/bin/sh

# Blank first, then yank HDMI out of the layout so a hotplug cannot wake it.
hyprctl dispatch dpms off

sleep 0.3

hyprctl keyword monitor "HDMI-A-1,disable"
