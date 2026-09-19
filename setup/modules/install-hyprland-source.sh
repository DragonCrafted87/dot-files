#!/usr/bin/env bash
# Build Hyprland v0.56.2 plus the hypr* ecosystem into an isolated prefix.
# Distro packages from install-hyprland-session stay in /usr. Ly gets a
# second session so the two stacks can be chosen independently.
#
# Fedora discussion #284 is the closest published dep list; package names
# below are the OpenMandriva translations of that set plus current hypr*
# build requirements (C++26, cmake, Qt6 for a few utilities).

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

HYPRLAND_SOURCE_VERSION="${HYPRLAND_SOURCE_VERSION:-v0.56.2}"
PREFIX="${HYPRLAND_SOURCE_PREFIX:-/opt/hyprland-0.56.2}"
SRC_ROOT="${HYPRLAND_SOURCE_SRC:-${DOTFILES_HOME}/.cache/hyprland-source}"
STAMP="${PREFIX}/share/hyprland-source/.dotfiles-stamp"
SESSION_DESKTOP_SRC="${SETUP_FILES_DIR}/hyprland-source/hyprland-source.desktop"
SESSION_WRAPPER_SRC="${SETUP_FILES_DIR}/hyprland-source/start-hyprland-source.sh"
LY_CUSTOM_DIR="/etc/ly/custom-sessions"
WAYLAND_SESSION_DIR="/usr/share/wayland-sessions"
