#!/usr/bin/env bash
# GUI packages shared by workstation, laptop, and htpc.
# thunar and similar live in Rock Extra; enable that repo in the installer
# if it is not already on.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user
ensure_packages \
    flatpak \
    thunar \
    thunar-volman \
    gvfs \
    ffmpeg \
    vlc \
    xdg-utils \
    desktop-file-utils \
    shared-mime-info \
    bluez \
    networkmanager \
    networkmanager-wifi \
    networkmanager-openvpn

# Rock 6.0 ships plasma6-* names for KF6 apps. The unprefixed names are
# leftover KF5 packages and conflict. Same dance as okular in
# install-workstation-packages.
install_kf6_or_plain() {
    local plasma6_name="$1"
    local plain_name="$2"

    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        log "${plasma6_name} / ${plain_name} package"
        return 0
    fi
    if rpm -q "$plasma6_name" >/dev/null 2>&1; then
        log "${plasma6_name} already installed"
        return 0
    fi
    if rpm -q "$plain_name" >/dev/null 2>&1; then
        log "${plain_name} already installed"
        return 0
    fi
    if dnf list --available "$plasma6_name" >/dev/null 2>&1; then
        ensure_packages "$plasma6_name"
    else
        ensure_packages "$plain_name"
    fi
}

# SUPER+E launches dolphin. KIO extras + kservice are what let it
# resolve "Open with" after plasma-workspace is gone.
install_kf6_or_plain plasma6-dolphin dolphin
install_kf6_or_plain plasma6-kio-extras kio-extras
install_kf6_or_plain plasma6-kde-cli-tools kde-cli-tools
