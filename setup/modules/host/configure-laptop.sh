#!/usr/bin/env bash
# Laptop subrole. Power profiles on battery-capable boxes.

set -euo pipefail
# shellcheck disable=SC1091
. "${REPO_ROOT:-$DOTFILES_ROOT}/setup/lib/lib.sh"

require_user
ensure_packages power-profiles-daemon
enable_service power-profiles-daemon.service
