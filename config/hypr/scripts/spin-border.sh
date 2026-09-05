#!/usr/bin/env bash
# Drive the active-window gradient around the frame.
# Needed on Hyprland 0.47–0.48 where animation = borderangle, ..., loop
# runs one revolution and then disconnects (issues #9251 / #9313).
#
# Seconds per full rotation. Match the look you wanted (~8s).
SECONDS_PER_TURN="${SECONDS_PER_TURN:-6}"

GRADIENT="rgb(305cde) rgb(560591)"

# ~45 updates/sec is enough at 2px border; cheaper than a 144 Hz compositor loop.
STEP_DEG=2
INTERVAL="$(awk -v s="$SECONDS_PER_TURN" -v d="$STEP_DEG" 'BEGIN { printf "%.4f", (s * d) / 360 }')"

angle=0
while true; do
    hyprctl -q keyword general:col.active_border "$GRADIENT ${angle}deg"
    angle=$(( (angle + STEP_DEG) % 360 ))
    sleep "$INTERVAL"
done
