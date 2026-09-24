#!/usr/bin/env bash
# Wrapper so role.sh can keep calling this module by name.
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib.sh"
require_user
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/prune-extra-packages.py" "$@"
