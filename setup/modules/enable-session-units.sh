#!/usr/bin/env bash
# Enable the Hyprland-related user units that are already in use.
# Distro audio/dbus sockets are left alone. network-mounts.service is
# custom and is only enabled if that unit file is present.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

enable_user_service hypridle.service
enable_user_service hyprpolkitagent.service
enable_user_service mako.service
