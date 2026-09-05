#!/usr/bin/env bash
# Role-specific Flatpaks. Discord on workstation and laptop; protontricks
# only on the workstation.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user
ensure_packages flatpak
ensure_flatpak_remote flathub https://flathub.org/repo/flathub.flatpakrepo

case "${OMV_ROLE:-}" in
    workstation)
        ensure_flatpak com.discordapp.Discord
        ensure_flatpak com.github.Matoking.protontricks
        ;;
    laptop)
        ensure_flatpak com.discordapp.Discord
        ;;
    *)
        log "no extra flatpaks for role ${OMV_ROLE:-unknown}"
        ;;
esac
