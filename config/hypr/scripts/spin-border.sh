#!/usr/bin/env bash
# Drive the active-window gradient around the frame.
# Needed on Hyprland 0.47–0.48 where animation = borderangle, ..., loop
# runs one revolution and then disconnects (issues #9251 / #9313).
# Hyprland 0.56+ uses lua borderangle loop instead; skip this script there.
set -euo pipefail

PREFIX="${HYPRLAND_SOURCE_PREFIX:-/usr/local}"

should_run() {
    local pid exe
    pid="$(pgrep -u "$(id -u)" -x Hyprland | head -n 1 || true)"
    [[ -n "$pid" ]] || return 0
    exe="$(readlink -f "/proc/${pid}/exe" 2>/dev/null || true)"
    # 0.56 borderangle covers both the /usr/local install and a leftover
    # /opt/hyprland tree from before the prefix move.
    [[ "$exe" != "${PREFIX}/bin/Hyprland" && "$exe" != "/usr/local/bin/Hyprland" && "$exe" != "/opt/hyprland/bin/Hyprland" ]]
}

if [[ "${1:-}" == "--should-run" ]]; then
    should_run
    exit $?
fi

should_run || exit 0

# Seconds per full rotation. Match the look you wanted (~8s).
SECONDS_PER_TURN="${SECONDS_PER_TURN:-6}"

# Palette from config/kitty/kitty.conf (Tango Dark color4 + color5).
GRADIENT="rgb(3465A4) rgb(75507B)"

# ~45 updates/sec is enough at 2px border; cheaper than a 144 Hz compositor loop.
STEP_DEG=2
INTERVAL="$(awk -v s="$SECONDS_PER_TURN" -v d="$STEP_DEG" 'BEGIN { printf "%.4f", (s * d) / 360 }')"

angle=0
while true; do
    hyprctl -q keyword general:col.active_border "$GRADIENT ${angle}deg"
    angle=$(( (angle + STEP_DEG) % 360 ))
    sleep "$INTERVAL"
done
