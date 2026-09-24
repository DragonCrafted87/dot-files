#!/usr/bin/env bash
# Server-only steps. Fill in as the rebuild settles (sshd, no GUI extras).

set -euo pipefail
# shellcheck disable=SC1091
. "${REPO_ROOT:-$DOTFILES_ROOT}/setup/lib/lib.sh"

require_user
log "server module has no extra steps yet"
