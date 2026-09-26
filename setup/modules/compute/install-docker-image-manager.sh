#!/usr/bin/env bash
# Back-compat wrapper. Docker image management lives under the
# artifact-repo subrole now.
#
#   ~/dot-files/setup/role.sh --enable-subrole artifact-repo

set -euo pipefail
# shellcheck disable=SC1091
. "${REPO_ROOT:-$DOTFILES_ROOT}/setup/lib/lib.sh"

require_user
warn "install-docker-image-manager is now artifact-repo; enabling that subrole"
enable_saved_subrole artifact-repo
run_module install-artifact-repo-manager
