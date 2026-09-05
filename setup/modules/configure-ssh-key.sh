#!/usr/bin/env bash
# Create an ed25519 key for this machine if one is not already present.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user
ensure_dir "${DOTFILES_HOME}/.ssh"
if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
    chmod 700 "${DOTFILES_HOME}/.ssh"
fi

if [[ -f "${SSH_KEY_PATH}" ]]; then
    log "ssh key already exists at ${SSH_KEY_PATH}"
    exit 0
fi

comment="${DOTFILES_USER}@$(hostname -s)"
log "generate ${SSH_KEY_PATH}"
run ssh-keygen -t ed25519 -f "${SSH_KEY_PATH}" -C "$comment" -N ""
if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
    chmod 600 "${SSH_KEY_PATH}"
    chmod 644 "${SSH_KEY_PATH}.pub"
fi
