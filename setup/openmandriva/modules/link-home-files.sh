#!/usr/bin/env bash
# Link non-secret home files shipped under files/home/.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

gitconfig_src="${SETUP_FILES_DIR}/home/gitconfig"
sshconfig_src="${SETUP_FILES_DIR}/home/ssh-config"

if [[ -f "$gitconfig_src" ]]; then
    if [[ -e "${DOTFILES_HOME}/.gitconfig" && ! -L "${DOTFILES_HOME}/.gitconfig" ]]; then
        log "back up existing ${DOTFILES_HOME}/.gitconfig"
        run mv "${DOTFILES_HOME}/.gitconfig" "${DOTFILES_HOME}/.gitconfig.distro"
    fi
    ensure_symlink "$gitconfig_src" "${DOTFILES_HOME}/.gitconfig"
else
    warn "missing ${gitconfig_src}"
fi

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
