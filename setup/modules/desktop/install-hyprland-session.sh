#!/usr/bin/env bash
# Ly, portals, and user session units for GUI roles.
# Hyprland itself comes from install-hyprland-source.sh into /usr/local
# after role reset has removed the distro hyprland rpm. This module does
# not install that rpm, uwsm, or pavucontrol-qt.

set -euo pipefail
# shellcheck disable=SC1091
. "${REPO_ROOT:-$DOTFILES_ROOT}/setup/lib/lib.sh"

require_user

# hypr-session-exec.sh picked /opt vs /usr/local. The units exec /usr/local.
remove_session_bin_dropins() {
    local stale dir
    shopt -s nullglob
    for stale in "${DOTFILES_HOME}/.config/systemd/user/"*.service.d/session-bin.conf; do
        dir="$(dirname "$stale")"
        log "remove ${stale}"
        run rm -f "$stale"
        rmdir "$dir" 2>/dev/null || true
    done
    shopt -u nullglob
}

# 0.56 draws the border from lua borderangle loop.
remove_spin_border_unit() {
    local unit link
    [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && return 0
    unit="${DOTFILES_HOME}/.config/systemd/user/workstation-spin-border.service"
    if systemctl --user is-active --quiet workstation-spin-border.service 2>/dev/null; then
        systemctl --user stop workstation-spin-border.service || true
    fi
    if [[ -e "$unit" ]]; then
        log "remove ${unit}"
        rm -f "$unit"
    fi
    shopt -s nullglob
    for link in "${DOTFILES_HOME}/.config/systemd/user/"*.wants/workstation-spin-border.service; do
        log "remove ${link}"
        rm -f "$link"
    done
    shopt -u nullglob
}

ensure_packages \
    ly \
    quickshell \
    kitty \
    xdg-desktop-portal \
    xdg-desktop-portal-gtk \
    pipewire \
    pipewire-pulse \
    wireplumber \
    playerctl \
    brightnessctl \
    ddcutil \
    wl-clipboard \
    grim \
    slurp \
    mako \
    fonts-ttf-hack \
    fonts-ttf-noto-emoji \
    fonts-ttf-dejavu \
    adobe-source-code-pro-fonts

disable_service sddm.service
disable_service plasma6-sddm.service
enable_service ly.service

# Bind unit for graphical-session.target. ly launches Hyprland.desktop, which
# never starts that target. Hyprland exec-once starts this unit; do not enable
# it for default.target (linger would claim a graphical session at boot).
# Role GUI apps are workstation-session.target / htpc-session.target.
src=""
shopt -s nullglob
for src in "${SETUP_FILES_DIR}/hypr/"*.service "${SETUP_FILES_DIR}/hypr/"*.target "${SETUP_FILES_DIR}/hypr/"*.timer; do
    install_user_unit "$src"
done
shopt -u nullglob
shopt -s nullglob
for src in "${SETUP_FILES_DIR}/hypr/"*.service.d/*.conf; do
    unit="$(basename "$(dirname "$src")")"
    install_user_dropin "${unit%.d}" "$src"
done
shopt -u nullglob
remove_session_bin_dropins
remove_spin_border_unit
if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
    systemctl --user daemon-reload
fi
