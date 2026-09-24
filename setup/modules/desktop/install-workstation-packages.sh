#!/usr/bin/env bash
# Dev / daily-driver extras for workstation and laptop.

set -euo pipefail
# shellcheck disable=SC1091
. "${REPO_ROOT:-$DOTFILES_ROOT}/setup/lib/lib.sh"

require_user

dest="/etc/yum.repos.d/vscode.repo"
if [[ ! -f "$dest" ]]; then
    log "add Visual Studio Code repo"
    if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
        sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
        sudo tee "$dest" >/dev/null <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
    fi
fi

ensure_packages \
    code \
    gcc \
    gcc-c++ \
    cmake \
    meson \
    ninja \
    docker \
    docker-compose \
    kubernetes-client \
    rclone \
    remmina \
    remmina-plugins-rdp \
    freerdp \
    solaar \
    piper \
    qalculate-gtk \
    aria2 \
    android-tools \
    guvcview

# Rock 6.0 ships plasma6-okular (KF6) and a leftover KF5 package still
# named okular. Installing the old name conflicts with the KF6 files.
install_kf6_or_plain plasma6-okular okular plasma6-okular-pdf plasma6-okular-common

# Override packaged .desktop files so the QS start menu can find Piper by
# Logitech fragments and Guvcview by camera/photo/video words. Also drop
# copies on the Desktop. install_user_desktop flags qs for a restart.
install_user_desktop "${SETUP_FILES_DIR}/applications/org.freedesktop.Piper.desktop"
install_user_desktop "${SETUP_FILES_DIR}/applications/guvcview.desktop"
