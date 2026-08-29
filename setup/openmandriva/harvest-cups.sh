#!/usr/bin/env bash
# Copy the live CUPS queue from this machine into the repo so other
# workstation/laptop installs can reuse it.
#
#   sudo ./setup/openmandriva/harvest-cups.sh

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest="${here}/files/cups"

if [[ "$(id -u)" -ne 0 ]]; then
    printf 'error: run with sudo so /etc/cups/printers.conf is readable\n' >&2
    exit 1
fi

if [[ ! -f /etc/cups/printers.conf ]]; then
    printf 'error: /etc/cups/printers.conf not found; is CUPS configured?\n' >&2
    exit 1
fi

# CUPS documents that printers.conf should be copied while the daemon is down.
systemctl stop cups.service cups.socket cups-browsed.service 2>/dev/null || true

mkdir -p "${dest}/ppd"
install -m 0640 /etc/cups/printers.conf "${dest}/printers.conf"
if [[ -d /etc/cups/ppd ]]; then
    cp -a /etc/cups/ppd/. "${dest}/ppd/" || true
fi
if [[ -f /etc/cups/classes.conf ]]; then
    install -m 0640 /etc/cups/classes.conf "${dest}/classes.conf"
fi

# Drop ownership back to the repo user if possible.
if [[ -n "${SUDO_USER:-}" ]]; then
    chown -R "${SUDO_USER}:${SUDO_USER}" "$dest"
fi

systemctl start cups.socket cups.service 2>/dev/null || true
systemctl start cups-browsed.service 2>/dev/null || true

printf '==> wrote %s\n' "$dest"
printf '    commit files/cups and re-run the workstation or laptop role\n'
printf '    DeviceURI lines in printers.conf are the live queue; edit if the\n'
printf '    printer address changes on the new network.\n'
