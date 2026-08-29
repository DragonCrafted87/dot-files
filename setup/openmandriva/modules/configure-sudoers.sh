#!/usr/bin/env bash
# Passwordless sudo drop-in for the primary user. Rewrites the file whole
# so re-runs do not append duplicate lines.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user
ensure_sudoers_dropin "${DOTFILES_USER}" "${DOTFILES_USER} ALL=(ALL) NOPASSWD: ALL"
