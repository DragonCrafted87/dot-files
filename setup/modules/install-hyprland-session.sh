#!/usr/bin/env bash
# Login and session stack for GUI roles, matching the current workstation.
# Distro Hyprland stays here. install-hyprland-source.sh adds a second
# prefix build that Ly can pick without replacing these rpms.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

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
