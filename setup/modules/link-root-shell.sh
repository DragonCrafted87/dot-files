#!/usr/bin/env bash
# Point root at the same bashrc tree the primary user uses.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

[[ -L "${DOTFILES_HOME}/.bashrc" ]] || die "${DOTFILES_HOME}/.bashrc is not linked yet; run link-dotfiles first"
[[ -L "${DOTFILES_HOME}/.bashrc.d" ]] || die "${DOTFILES_HOME}/.bashrc.d is not linked yet; run link-dotfiles first"

if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
    printf 'dry-run: sudo ln -sfn %s /root/.bashrc\n' "${DOTFILES_HOME}/.bashrc"
    printf 'dry-run: sudo ln -sfn %s /root/.bashrc.d\n' "${DOTFILES_HOME}/.bashrc.d"
    exit 0
fi

if [[ "$(sudo readlink /root/.bashrc 2>/dev/null || true)" != "${DOTFILES_HOME}/.bashrc" ]]; then
    log "link /root/.bashrc -> ${DOTFILES_HOME}/.bashrc"
    sudo ln -sfn "${DOTFILES_HOME}/.bashrc" /root/.bashrc
fi

if [[ "$(sudo readlink /root/.bashrc.d 2>/dev/null || true)" != "${DOTFILES_HOME}/.bashrc.d" ]]; then
    log "link /root/.bashrc.d -> ${DOTFILES_HOME}/.bashrc.d"
    sudo ln -sfn "${DOTFILES_HOME}/.bashrc.d" /root/.bashrc.d
fi
