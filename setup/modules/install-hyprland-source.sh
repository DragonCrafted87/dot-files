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

# Pinned to the Debian-Hyprland / Fedora COPR 0.56.2 set. Override a
# single tag without editing the module.
AQUAMARINE_TAG="${AQUAMARINE_TAG:-v0.15.1}"
HYPRCURSOR_TAG="${HYPRCURSOR_TAG:-v0.1.13}"
HYPRGRAPHICS_TAG="${HYPRGRAPHICS_TAG:-v0.5.1}"
HYPRIDLE_TAG="${HYPRIDLE_TAG:-v0.1.8}"
HYPRLAND_GUIUTILS_TAG="${HYPRLAND_GUIUTILS_TAG:-v0.2.2}"
HYPRLAND_PROTOCOLS_TAG="${HYPRLAND_PROTOCOLS_TAG:-v0.7.0}"
HYPRLAND_QT_SUPPORT_TAG="${HYPRLAND_QT_SUPPORT_TAG:-v0.1.0}"
HYPRLAND_TAG="${HYPRLAND_TAG:-v0.56.2}"
HYPRLANG_TAG="${HYPRLANG_TAG:-v0.6.8}"
HYPRLAUNCHER_TAG="${HYPRLAUNCHER_TAG:-v0.1.6}"
HYPRLOCK_TAG="${HYPRLOCK_TAG:-v0.9.6}"
HYPRPAPER_TAG="${HYPRPAPER_TAG:-v0.8.4}"
HYPRPICKER_TAG="${HYPRPICKER_TAG:-v0.4.7}"
HYPRPOLKITAGENT_TAG="${HYPRPOLKITAGENT_TAG:-v0.2.0}"
HYPRPWCENTER_TAG="${HYPRPWCENTER_TAG:-v0.1.2}"
HYPRQT6ENGINE_TAG="${HYPRQT6ENGINE_TAG:-v0.1.0}"
HYPRSHUTDOWN_TAG="${HYPRSHUTDOWN_TAG:-v0.1.1}"
HYPRSUNSET_TAG="${HYPRSUNSET_TAG:-v0.4.0}"
HYPRSYSTEMINFO_TAG="${HYPRSYSTEMINFO_TAG:-v0.2.0}"
HYPRTOOLKIT_TAG="${HYPRTOOLKIT_TAG:-v0.6.0}"
HYPRUTILS_TAG="${HYPRUTILS_TAG:-v0.14.2}"
HYPRWAYLAND_SCANNER_TAG="${HYPRWAYLAND_SCANNER_TAG:-v0.4.6}"
HYPRWIRE_TAG="${HYPRWIRE_TAG:-v0.3.1}"
XDPH_TAG="${XDPH_TAG:-v1.4.1}"
