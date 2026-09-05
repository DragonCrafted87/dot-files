#!/usr/bin/env bash
# HTPC-only steps. Fill in as the rebuild settles (media session, etc.).

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user
log "htpc module has no extra steps yet"
