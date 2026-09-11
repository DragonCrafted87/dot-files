#!/usr/bin/env bash
# Keep the user systemd instance after logout so user units (BOINC, and
# anything else under ~/.config/systemd/user) survive a disconnected session.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

if ! command -v loginctl >/dev/null 2>&1; then
    warn "loginctl not present; skip linger"
    exit 0
fi

if loginctl show-user "${DOTFILES_USER}" -p Linger 2>/dev/null | grep -qx 'Linger=yes'; then
    exit 0
fi

log "enable lingering for ${DOTFILES_USER}"
run sudo loginctl enable-linger "${DOTFILES_USER}"
