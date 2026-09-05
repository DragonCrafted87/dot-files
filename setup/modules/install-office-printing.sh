#!/usr/bin/env bash
# LibreOffice apps, CUPS, and the harvested printer queue.
# Avoid task-printing and the libreoffice metapackage; those pull Java,
# nmap, and a pile of unneeded printer drivers.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

ensure_packages \
    cups \
    cups-filters \
    cups-browsed \
    libreoffice-writer \
    libreoffice-calc \
    libreoffice-impress \
    libreoffice-draw \
    libreoffice-math \
    libreoffice-common

cups_src="${SETUP_FILES_DIR}/cups"
if [[ ! -f "${cups_src}/printers.conf" ]]; then
    warn "no harvested printer config at ${cups_src}/printers.conf"
    warn "on the current workstation run: ${SETUP_DIR}/harvest-cups.sh"
    enable_service cups.socket
    enable_service cups.service
    exit 0
fi

log "install printer config from ${cups_src}"
if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
    exit 0
fi

# CUPS documents that printers.conf must be written while the daemon is down.
sudo systemctl stop cups-browsed.service cups.service cups.socket 2>/dev/null || true
sudo install -d -m 0755 /etc/cups /etc/cups/ppd
sudo install -m 0640 "${cups_src}/printers.conf" /etc/cups/printers.conf
if [[ -d "${cups_src}/ppd" ]]; then
    sudo cp -a "${cups_src}/ppd/." /etc/cups/ppd/
fi
if [[ -f "${cups_src}/classes.conf" ]]; then
    sudo install -m 0640 "${cups_src}/classes.conf" /etc/cups/classes.conf
fi

sudo systemctl reset-failed cups.socket cups.service cups-browsed.service 2>/dev/null || true
sleep 1
enable_service cups.socket
enable_service cups.service
if ! sudo systemctl start cups.socket cups.service; then
    sudo systemctl reset-failed cups.socket cups.service
    sleep 2
    sudo systemctl start cups.socket cups.service
fi
sudo systemctl enable --now cups-browsed.service 2>/dev/null || true
