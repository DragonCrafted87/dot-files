#!/usr/bin/env bash
# Current OpenMandriva kdeconnect ships the tray app, not a PATH daemon.
# The indicator talks to the D-Bus service and keeps the session alive.

set -euo pipefail

for bin in \
    /usr/bin/kdeconnect-indicator \
    /sbin/kdeconnect-indicator \
    /usr/bin/kdeconnectd \
    /usr/libexec/kdeconnectd \
    /usr/lib/kdeconnectd \
    /usr/lib64/libexec/kdeconnectd; do
    if [[ -x "$bin" ]]; then
        exec "$bin"
    fi
done

if command -v kdeconnect-indicator >/dev/null 2>&1; then
    exec kdeconnect-indicator
fi

exit 0
