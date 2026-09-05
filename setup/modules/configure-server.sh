#!/usr/bin/env bash
# Server-only steps. Fill in as the rebuild settles (sshd, no GUI extras).

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user
log "server module has no extra steps yet"
