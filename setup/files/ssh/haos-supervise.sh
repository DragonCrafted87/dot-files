#!/bin/sh
# /etc/systemd/system is erofs on Home Assistant OS, so this process is
# the key refresh and the tty1 banner. haos-udev.sh and haos-activate.sh
# start it with systemd-run. A bad key fetch retries in two minutes. A
# good fetch waits twelve hours.

set -eu

root="/mnt/overlay/dot-files"
sync="${root}/sync-github-keys.sh"
lock="${root}/haos-console-lock.sh"
pidfile="${root}/haos-console-lock.pid"
keys_user=DragonCrafted87

start_lock() {
    if [ -s "$pidfile" ]; then
        old="$(cat "$pidfile" 2>/dev/null || true)"
        if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
            return 0
        fi
    fi
    HAOS_CONSOLE_DEVICE=/dev/tty1 "$lock" &
    printf '%s\n' "$!" >"$pidfile"
}

systemctl mask --runtime --now ha-cli@tty1.service getty@tty1.service
start_lock

# The boot-time udev event can run before DHCP. The role also syncs once
# immediately, because an SSH session means the network is already up.
sleep 120
while true; do
    if GITHUB_KEYS_USER="$keys_user" DOTFILES_HOME=/root "$sync"; then
        sleep 43200
    else
        sleep 120
    fi
done
