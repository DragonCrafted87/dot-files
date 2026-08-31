#!/usr/bin/env bash
# Dev / daily-driver extras for workstation and laptop.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

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
    aria2

# Rock 6.0 ships plasma6-okular (KF6) and a leftover KF5 package still
# named okular. Installing the old name conflicts with the KF6 files.
if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
    log "okular package"
elif rpm -q plasma6-okular >/dev/null 2>&1; then
    log "plasma6-okular already installed"
elif rpm -q okular >/dev/null 2>&1 && ! rpm -q plasma6-okular-common >/dev/null 2>&1; then
    log "okular already installed"
elif dnf list --available plasma6-okular >/dev/null 2>&1; then
    ensure_packages plasma6-okular plasma6-okular-pdf plasma6-okular-common
else
    ensure_packages okular
fi
