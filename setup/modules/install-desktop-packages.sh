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

# SUPER+E launches dolphin. KIO extras + kservice are what let it
# resolve "Open with" after plasma-workspace is gone.
install_kf6_or_plain plasma6-dolphin dolphin
install_kf6_or_plain plasma6-kio-extras kio-extras
install_kf6_or_plain plasma6-kde-cli-tools kde-cli-tools

# Fresh machines have no leftover Plasma theme. These give Dolphin / Okular
# Breeze Dark plus the kde Qt platform plugin that reads ~/.config/kdeglobals.
install_kf6_or_plain plasma6-integration plasma-integration
install_kf6_or_plain kf6-breeze-icons breeze-icon-theme
install_kf6_or_plain plasma6-breeze breeze
