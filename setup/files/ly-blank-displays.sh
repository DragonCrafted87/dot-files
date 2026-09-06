#!/usr/bin/env bash
# Called by Ly inactivity_cmd. setterm --blank force only talks to a VT
and does not put DisplayPort panels to sleep when Ly is on KMS.
set -u

for node in /sys/class/drm/card*-*/dpms; do
    [[ -e "$node" ]] || continue
    printf 'Off\n' >"$node" 2>/dev/null || true
done

if command -v setterm >/dev/null 2>&1; then
    for tty in /dev/tty1 /dev/tty2 /dev/tty3 /dev/tty7; do
        [[ -c "$tty" ]] || continue
        setterm --blank force --powersave powerdown <"$tty" >"$tty" 2>/dev/null || true
    done
fi
