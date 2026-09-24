#!/usr/bin/env bash
# Enable the Hyprland-related user units that are already in use.
# Distro audio/dbus sockets are left alone. These WantedBy
# graphical-session.target, which hyprland-session.service binds after
# login (ly -> Hyprland.desktop does not start that target).
# network-mounts.service is custom and is enabled in install-network-mounts.

set -euo pipefail
# shellcheck disable=SC1091
. "${REPO_ROOT:-$DOTFILES_ROOT}/setup/lib/lib.sh"

require_user

enable_user_service hypridle.service
enable_user_service hyprpolkitagent.service
enable_user_service mako.service
