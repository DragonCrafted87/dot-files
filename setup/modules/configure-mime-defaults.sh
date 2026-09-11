#!/usr/bin/env bash
# Give Dolphin / xdg-open a MIME map after plasma-workspace is removed.
# Hyprland env (XDG_CURRENT_DESKTOP=Hyprland:KDE) is the other half.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

src="${SETUP_FILES_DIR}/mime/mimeapps.list"
dest="${CONFIG_TARGET_DIR}/mimeapps.list"

if [[ ! -f "$src" ]]; then
    die "missing ${src}"
fi

ensure_dir "${CONFIG_TARGET_DIR}"

write_mimeapps=0
if [[ ! -f "$dest" ]]; then
    write_mimeapps=1
elif grep -q '^# managed by dot-files configure-mime-defaults' "$dest"; then
    if ! cmp -s "$src" "$dest"; then
        write_mimeapps=1
    fi
else
    warn "leave existing ${dest} (not managed by this module)"
fi

if [[ "$write_mimeapps" -eq 1 ]]; then
    log "write ${dest}"
    if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
        install -m 0644 "$src" "$dest"
    fi
fi

if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
    exit 0
fi

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${DOTFILES_HOME}/.local/share/applications" 2>/dev/null || true
fi

# Rebuild KService cache so Dolphin sees LibreOffice / Okular .desktop files.
if command -v kbuildsycoca6 >/dev/null 2>&1; then
    log "kbuildsycoca6"
    kbuildsycoca6 --noincremental >/dev/null 2>&1 || kbuildsycoca6 || true
elif command -v kbuildsycoca5 >/dev/null 2>&1; then
    log "kbuildsycoca5"
    kbuildsycoca5 --noincremental >/dev/null 2>&1 || kbuildsycoca5 || true
else
    warn "kbuildsycoca6 not on PATH; Dolphin may need a session restart after first install"
fi
