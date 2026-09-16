#!/usr/bin/env bash
# Workstation-only gaming stack. Needs Rock Non-free for Steam.
# Proton games should launch through
# ~/.config/hypr/scripts/steam-proton-wrap.sh so they follow the active
# Hyprland display profile (desk / theater / laptop panel).

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
