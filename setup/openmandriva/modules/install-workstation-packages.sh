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
    solaar \
    piper \
    qalculate-gtk \
    aria2

# Rolling renamed this to okular; Rock 6.0 still uses plasma6-okular.
if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
    log "okular package"
elif dnf list --available okular >/dev/null 2>&1 || rpm -q okular >/dev/null 2>&1; then
    ensure_packages okular
else
    ensure_packages plasma6-okular plasma6-okular-pdf plasma6-okular-common
fi
