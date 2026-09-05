#!/usr/bin/env bash
# If gh is already logged in on this box, make sure the host key is
# uploaded. init-remote.sh does that from the working computer, so a
# missing login here is not an error.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

[[ -f "${SSH_KEY_PATH}.pub" ]] || die "missing ${SSH_KEY_PATH}.pub; run configure-ssh-key first"

if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
    printf 'dry-run: gh ssh-key add %s if gh is logged in\n' "${SSH_KEY_PATH}.pub"
    exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
    log "gh not installed on this box; key should already be on GitHub from init-remote.sh"
    exit 0
fi

if ! gh auth status --hostname github.com >/dev/null 2>&1; then
    log "gh is not logged in on this box; skip remote key upload"
    exit 0
fi

pubkey="$(awk '{print $2}' "${SSH_KEY_PATH}.pub")"
if gh ssh-key list 2>/dev/null | grep -Fq "$pubkey"; then
    log "ssh key already registered on GitHub"
    exit 0
fi

title="$(hostname -s)-$(date +%F)"
log "add ssh key to GitHub as ${title}"
gh ssh-key add "${SSH_KEY_PATH}.pub" --title "$title"
