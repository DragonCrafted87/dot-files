#!/usr/bin/env bash
# Allow the session to drive Logitech Litra Glow lamps over hidraw.
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib.sh"

require_user

src="${SETUP_FILES_DIR}/litra/99-litra-glow.rules"
dest="/etc/udev/rules.d/99-litra-glow.rules"

if [[ ! -f "$src" ]]; then
    warn "missing ${src}"
    exit 0
fi

if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
    :
else
    log "udev ${dest}"
    run sudo install -m 0644 "$src" "$dest"
    run sudo udevadm control --reload-rules
    run sudo udevadm trigger --subsystem-match=hidraw || true
fi

if getent group video >/dev/null; then
    if ! id -nG "${DOTFILES_USER}" | grep -qw video; then
        log "add ${DOTFILES_USER} to video"
        run sudo gpasswd -a "${DOTFILES_USER}" video
    fi
fi
