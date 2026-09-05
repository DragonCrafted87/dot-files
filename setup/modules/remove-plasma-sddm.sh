#!/usr/bin/env bash
# Drop the stock Plasma / SDDM stack on every role.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

disable_service sddm.service
disable_service plasma6-sddm.service

remove_packages \
    task-plasma \
    task-plasma6 \
    task-plasma6-x11 \
    task-plasma6-wayland \
    sddm \
    sddm-kcm \
    sddm-theme-breeze \
    plasma6-sddm \
    plasma6-sddm-kcm \
    plasma6-sddm-theme-breeze \
    plasma-desktop \
    plasma-workspace \
    plasma6-desktop \
    plasma6-workspace
