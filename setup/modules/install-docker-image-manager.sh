#!/usr/bin/env bash
# Back-compat wrapper. Docker image management lives under the
# artifact-repo subrole now.
#
#   ~/dot-files/setup/role.sh --enable-subrole artifact-repo

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/subroles.sh"

require_user
warn "install-docker-image-manager is now artifact-repo; enabling that subrole"
enable_saved_subrole artifact-repo
run_module install-artifact-repo-manager
