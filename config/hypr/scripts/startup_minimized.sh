#!/bin/sh

# ================== CONFIGURATION ==================
# Add apps here (command to run). One per line.
APPS_TO_MINIMIZE=(
    "steam"
    "/var/lib/flatpak/app/com.discordapp.Discord/current/active/export/bin/com.discordapp.Discord"
    # "spotify"
    "code"
    # "firefox"
)

# Delay after launching (seconds) - increase if apps are slow to start
LAUNCH_DELAY=25
# ===================================================

PIDS=()

echo "Launching apps to minimize..."

for app in "${APPS_TO_MINIMIZE[@]}"; do
    echo "Starting: $app"
    $app &
    pid=$!
    PIDS+=("$pid")
    echo "  → PID: $pid"
done

echo "Waiting $LAUNCH_DELAY seconds for windows to appear..."
sleep "$LAUNCH_DELAY"

# Now minimize windows belonging to our launched PIDs
echo "Moving windows to minimized workspace..."

hyprctl clients -j | jq -r '.[] | "\(.pid)|\(.address)"' | while IFS='|' read -r pid address; do
    for target_pid in "${PIDS[@]}"; do
        if [ "$pid" = "$target_pid" ]; then
            echo "Minimizing window (PID $pid) → address $address"
            hyprctl dispatch movetoworkspacesilent special:minimized,address:"$address" 2>/dev/null
            break
        fi
    done
done

echo "Startup minimization complete."