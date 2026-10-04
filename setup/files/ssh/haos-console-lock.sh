#!/bin/sh
# Hold the HDMI console. ha-cli@tty1 accepts commands with no password,
# and the host root password is empty, so a getty on tty1 is not a lock.
# The supervisor sets HAOS_CONSOLE_DEVICE. Left unset, the banner stays
# on stdout so a workstation test can read it.

set -eu

if [ -n "${HAOS_CONSOLE_DEVICE:-}" ]; then
    exec <"${HAOS_CONSOLE_DEVICE}" >"${HAOS_CONSOLE_DEVICE}" 2>&1
    printf '\033[2J\033[H'
fi

name=""
if [ -r /etc/hostname ]; then
    name="$(sed -n '1s/\..*//p' /etc/hostname 2>/dev/null || true)"
fi
if [ -z "$name" ]; then
    name="host"
fi
printf '\n%s console is locked.\nUse SSH on port 22222.\n\n' "$name"

# A closed tty makes read fail. Sleep instead of spinning.
while true; do
    if ! read -r _; then
        sleep 3600
    fi
done
