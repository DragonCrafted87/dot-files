#!/usr/bin/env bash
# Workstation-only gaming stack. Needs Rock Non-free for Steam.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user
ensure_packages \
    steam \
    wine \
    gamescope \
    dxvk \
    protonplus
