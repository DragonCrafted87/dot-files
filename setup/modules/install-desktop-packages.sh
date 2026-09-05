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
    bluez \
    networkmanager \
    networkmanager-wifi \
    networkmanager-openvpn
