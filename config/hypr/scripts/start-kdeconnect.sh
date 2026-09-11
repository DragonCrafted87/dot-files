#!/usr/bin/env bash
# Start the KDE Connect daemon from whichever path OpenMandriva ships.

set -euo pipefail

for bin in /usr/bin/kdeconnectd /usr/libexec/kdeconnectd /usr/lib/kdeconnectd; do
    if [[ -x "$bin" ]]; then
        exec "$bin"
    fi
done

exit 0
