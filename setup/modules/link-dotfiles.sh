#!/usr/bin/env bash
# Clone or update the dot-files repo and link the shell entrypoints.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

ensure_repo "${DOTFILES_REPO_URL}" "${DOTFILES_DIR}"

bashrc_source="${DOTFILES_DIR}/${DOTFILES_BASHRC}"
if [[ ! -f "$bashrc_source" ]]; then
    bashrc_source="${DOTFILES_DIR}/shell/linux.bashrc"
fi
[[ -f "$bashrc_source" ]] || die "missing ${bashrc_source}"
[[ -d "${DOTFILES_DIR}/bashrc.d" ]] || die "missing ${DOTFILES_DIR}/bashrc.d"

# Replace a regular ~/.bashrc from the distro installer, but refuse to
# clobber any other unexpected regular file.
if [[ -e "${DOTFILES_HOME}/.bashrc" && ! -L "${DOTFILES_HOME}/.bashrc" ]]; then
    log "back up existing ${DOTFILES_HOME}/.bashrc"
    run mv "${DOTFILES_HOME}/.bashrc" "${DOTFILES_HOME}/.bashrc.distro"
fi
ensure_symlink "$bashrc_source" "${DOTFILES_HOME}/.bashrc"
ensure_symlink "${DOTFILES_DIR}/bashrc.d" "${DOTFILES_HOME}/.bashrc.d"
ensure_dir "${DOTFILES_HOME}/bin"
