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
        ensure_flatpak com.obsproject.Studio
        ensure_flatpak com.obsproject.Studio.Plugin.BackgroundRemoval
        ;;
    *)
        log "no extra flatpaks for role ${OMV_ROLE:-unknown}"
        ;;
esac

# Theme via env only. Binding xdg-config/gtk-3.0 makes bwrap try to
# replace ~/.config/gtk-3.0 with a symlink and abort when that path is
# already a directory (BOINC manager).
if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
    log "dry-run: flatpak override GTK/Qt theme env"
else
    log "flatpak override user theme env"
    flatpak override --user --env=GTK_THEME=Adwaita:dark || true
    flatpak override --user --env=QT_QPA_PLATFORMTHEME=kde || true
    flatpak override --user --env=XCURSOR_THEME=breeze_cursors || true
    flatpak override --user --nofilesystem=xdg-config/gtk-3.0 || true
    flatpak override --user --nofilesystem=xdg-config/gtk-4.0 || true
    flatpak override --user --nofilesystem=xdg-config/gtk-3.0 edu.berkeley.BOINC || true
    flatpak override --user --nofilesystem=xdg-config/gtk-4.0 edu.berkeley.BOINC || true
fi
