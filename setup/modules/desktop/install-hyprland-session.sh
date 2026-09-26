#!/usr/bin/env bash
# Login and session stack for GUI roles, matching the current workstation.

set -euo pipefail
# shellcheck disable=SC1091
. "${REPO_ROOT:-$DOTFILES_ROOT}/setup/lib/lib.sh"

require_user

ensure_packages \
    ly \
    hyprland \
    hyprland-qtutils \
    hypridle \
    hyprlock \
    hyprpicker \
    hyprpolkitagent \
    hyprcursor \
    quickshell \
    kitty \
    uwsm \
    xdg-desktop-portal \
    xdg-desktop-portal-hyprland \
    xdg-desktop-portal-gtk \
    pipewire \
    pipewire-pulse \
    wireplumber \
    pavucontrol-qt \
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

# Optional on current Rock/OMV; install-hyprshutdown.sh builds it if missing.
if dnf list --available hyprshutdown >/dev/null 2>&1 || rpm -q hyprshutdown >/dev/null 2>&1; then
    ensure_packages hyprshutdown
fi

disable_service sddm.service
disable_service plasma6-sddm.service
enable_service ly.service

# Bind unit for graphical-session.target. ly launches Hyprland.desktop, which
# never starts that target. Hyprland exec-once starts this unit; do not enable
# it for default.target (linger would claim a graphical session at boot).
# Role GUI apps are workstation-session.target / htpc-session.target.
src=""
shopt -s nullglob
for src in "${SETUP_FILES_DIR}/hypr/"*.service "${SETUP_FILES_DIR}/hypr/"*.target; do
    install_user_unit "$src"
done
shopt -u nullglob
install_user_dropin xdg-document-portal.service \
    "${SETUP_FILES_DIR}/hypr/xdg-document-portal.service.d/timeout-stop.conf"
if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
    systemctl --user daemon-reload
fi
