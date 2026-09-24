#!/usr/bin/env bash
# Set the system timezone if it is not already correct.

set -euo pipefail
# shellcheck disable=SC1091
. "${REPO_ROOT:-$DOTFILES_ROOT}/setup/lib/lib.sh"

require_user
ensure_timezone "${DOTFILES_TIMEZONE}"
