#!/bin/bash

# Script to turn off laptop display after CLI inactivity on openSUSE Leap 15.6
# Works at TTY/login screen (no WM) and in Sway Wayland sessions

# Check for inotifywait (for input monitoring)
if ! command -v inotifywait &> /dev/null; then
    echo "Error: inotifywait not found. Please install inotify-tools."
    echo "Run: sudo zypper install inotify-tools"
    exit 1
fi

# Check for vbetool (for TTY display control)
if ! command -v vbetool &> /dev/null; then
    echo "Error: vbetool not found. Please install vbetool."
    echo "Run: sudo zypper install vbetool"
    exit 1
fi

# Check for wlr-randr (for Sway Wayland sessions)
if ! command -v wlr-randr &> /dev/null; then
    echo "Warning: wlr-randr not found. Sway display control will not work."
    echo "Run: sudo zypper install wlr-randr"
fi

# Idle time threshold in seconds (e.g., 300 seconds = 5 minutes)
IDLE_THRESHOLD=300

# Input devices directory
INPUT_DIR="/dev/input"

echo "Starting display idle monitor. Display will turn off after $IDLE_THRESHOLD seconds of inactivity."

# Function to turn off display based on environment
turn_off_display() {
    if [ -n "$WAYLAND_DISPLAY" ] && command -v wlr-randr &> /dev/null; then
        # In a Wayland (Sway) session
        OUTPUT=$(wlr-randr | grep -oP '^\S+' | head -n 1)
        if [ -n "$OUTPUT" ]; then
            wlr-randr --output "$OUTPUT" --off
        else
            echo "No Wayland output detected."
        fi
    else
        # In TTY or no WM (use vbetool for DPMS off)
        vbetool dpms off
    fi
}

# Function to turn on display based on environment
turn_on_display() {
    if [ -n "$WAYLAND_DISPLAY" ] && command -v wlr-randr &> /dev/null; then
        # In a Wayland (Sway) session
        OUTPUT=$(wlr-randr | grep -oP '^\S+' | head -n 1)
        if [ -n "$OUTPUT" ]; then
            wlr-randr --output "$OUTPUT" --on
        fi
    else
        # In TTY or no WM (use vbetool for DPMS on)
        vbetool dpms on
    fi
}

# Main loop
last_activity=$(date +%s)

while true; do
    # Monitor input devices for activity with a timeout
    timeout $((IDLE_THRESHOLD + 10)) inotifywait -q -e modify "$INPUT_DIR"/event* > /dev/null 2>&1
    current_time=$(date +%s)

    # If inotifywait timed out (no input for IDLE_THRESHOLD + 10 seconds)
    if [ $? -eq 2 ]; then
        turn_off_display
        last_activity=$current_time
    else
        # Input detected, ensure display is on
        turn_on_display
        last_activity=$current_time
    fi
done
