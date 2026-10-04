#!/bin/sh
# Hold the HDMI console. ha-cli@tty1 accepts commands with no password,
# and the host root password is empty, so a getty on tty1 is not a lock.

set -eu

name="$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf '%s' host)"
printf '\n%s console is locked.\nUse SSH on port 22222.\n\n' "$name"

# A closed tty makes read fail. Sleep instead of spinning.
while true; do
    if ! read -r _; then
        sleep 3600
    fi
done
