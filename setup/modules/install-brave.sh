#!/usr/bin/env bash
# Brave repo + package. Used by workstation, laptop, and htpc.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

dest="/etc/yum.repos.d/brave-browser.repo"
if [[ ! -f "$dest" ]]; then
    log "add Brave repo"
    if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
        sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
        sudo tee "$dest" >/dev/null <<'EOF'
[brave-browser]
name=Brave Browser
baseurl=https://brave-browser-rpm-release.s3.brave.com/x86_64
enabled=1
gpgcheck=1
gpgkey=https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
EOF
    fi
fi

ensure_packages brave-browser
