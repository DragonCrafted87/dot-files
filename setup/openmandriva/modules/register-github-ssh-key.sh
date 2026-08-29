#!/usr/bin/env bash
# Authenticate GitHub CLI if needed, then upload this machine's public key.
# gh auth login --web is meant to be completed on the working computer
# you are ssh'd in from.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

if ! command -v gh >/dev/null 2>&1; then
    ensure_packages gh
fi

[[ -f "${SSH_KEY_PATH}.pub" ]] || die "missing ${SSH_KEY_PATH}.pub; run configure-ssh-key first"

if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
    printf 'dry-run: gh auth login --hostname github.com --git-protocol ssh --web\n'
    printf 'dry-run: gh ssh-key add %s\n' "${SSH_KEY_PATH}.pub"
    exit 0
fi

if ! gh auth status --hostname github.com >/dev/null 2>&1; then
    log "log in to GitHub with the device code on your working computer"
    gh auth login --hostname github.com --git-protocol ssh --web
fi

pubkey="$(awk '{print $2}' "${SSH_KEY_PATH}.pub")"
if gh ssh-key list 2>/dev/null | grep -Fq "$pubkey"; then
    log "ssh key already registered on GitHub"
    exit 0
fi

title="$(hostname -s)-$(date +%Y%m%d)"
log "add ssh key to GitHub as ${title}"
gh ssh-key add "${SSH_KEY_PATH}.pub" --title "$title"
