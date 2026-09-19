#!/usr/bin/env bash
# First common module. Fresh Rock installs do not ship git; update-role
# and lib.sh git helpers need it before anything else runs.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

if command -v git >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
    log "git and curl already on PATH"
    exit 0
fi

ensure_packages git curl
command -v git >/dev/null 2>&1 || die "git is still missing after dnf install"
