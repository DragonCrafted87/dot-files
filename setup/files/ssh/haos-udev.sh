#!/bin/sh
# udev kills RUN programs when the event ends, including their children.
# systemd-run gives the supervisor to pid 1 and returns.

set -eu

if systemctl is-active -q haos-dot-files.service; then
    exit 0
fi
systemd-run --unit=haos-dot-files.service --collect \
    --description='Home Assistant OS dot-files' \
    /mnt/overlay/dot-files/haos-supervise.sh || true
exit 0
