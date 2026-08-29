#!/usr/bin/env bash
# LibreOffice, CUPS, and the harvested printer queue for workstation/laptop.
# Run harvest-cups.sh on the current machine once and commit files/cups/.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

ensure_packages \
    cups \
    cups-filters \
    cups-browsed \
    task-printing \
    libreoffice \
    libreoffice-writer \
    libreoffice-calc \
    libreoffice-impress \
    libreoffice-draw \
    libreoffice-math \
    libreoffice-common

enable_service cups.service
enable_service cups.socket

cups_src="${SETUP_FILES_DIR}/cups"
if [[ ! -f "${cups_src}/printers.conf" ]]; then
    warn "no harvested printer config at ${cups_src}/printers.conf"
    warn "on the current workstation run: ${OPENMANDRIVA_SETUP_DIR}/harvest-cups.sh"
    exit 0
fi

log "install printer config from ${cups_src}"
if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
    exit 0
fi

# CUPS documents that printers.conf must be written while the daemon is down.
sudo systemctl stop cups.service cups.socket cups-browsed.service 2>/dev/null || true
sudo install -d -m 0755 /etc/cups /etc/cups/ppd
sudo install -m 0640 "${cups_src}/printers.conf" /etc/cups/printers.conf
if [[ -d "${cups_src}/ppd" ]]; then
    sudo cp -a "${cups_src}/ppd/." /etc/cups/ppd/
fi
if [[ -f "${cups_src}/classes.conf" ]]; then
    sudo install -m 0640 "${cups_src}/classes.conf" /etc/cups/classes.conf
fi
sudo systemctl start cups.socket cups.service
sudo systemctl start cups-browsed.service 2>/dev/null || true
