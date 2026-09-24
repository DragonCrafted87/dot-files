#!/usr/bin/env bash
# Link non-secret home files shipped under files/home/.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib.sh"

require_user

link_home() {
    local src="$1"
    local dest="$2"
    if [[ ! -f "$src" ]]; then
        warn "missing ${src}"
        return 0
    fi
    if [[ -e "$dest" && ! -L "$dest" ]]; then
        log "back up existing ${dest}"
        run mv "$dest" "${dest}.distro"
    fi
    ensure_symlink "$src" "$dest"
}

link_home "${SETUP_FILES_DIR}/home/gitconfig" "${DOTFILES_HOME}/.gitconfig"
link_home "${SETUP_FILES_DIR}/home/nanorc" "${DOTFILES_HOME}/.nanorc"
link_home "${SETUP_FILES_DIR}/home/dircolors" "${DOTFILES_HOME}/.dircolors"
link_home "${SETUP_FILES_DIR}/home/gtkrc-2.0" "${DOTFILES_HOME}/.gtkrc-2.0"

sshconfig_src="${SETUP_FILES_DIR}/home/ssh-config"
if [[ -f "$sshconfig_src" ]]; then
    ensure_dir "${DOTFILES_HOME}/.ssh"
    run chmod 700 "${DOTFILES_HOME}/.ssh"
    if [[ -e "${DOTFILES_HOME}/.ssh/config" && ! -L "${DOTFILES_HOME}/.ssh/config" ]]; then
        log "back up existing ${DOTFILES_HOME}/.ssh/config"
        run mv "${DOTFILES_HOME}/.ssh/config" "${DOTFILES_HOME}/.ssh/config.distro"
    fi
    ensure_symlink "$sshconfig_src" "${DOTFILES_HOME}/.ssh/config"
else
    warn "missing ${sshconfig_src}"
fi
