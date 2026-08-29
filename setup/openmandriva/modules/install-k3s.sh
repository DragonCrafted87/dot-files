#!/usr/bin/env bash
# k3s on servers and HTPCs. Default is a single-node server.
# To join an existing cluster instead:
#   K3S_URL=https://leader:6443 K3S_TOKEN=... ./modules/install-k3s.sh

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
    printf 'dry-run: install k3s if missing and raise CPU weight\n'
    exit 0
fi

if ! command -v k3s >/dev/null 2>&1; then
    log "install k3s"
    if [[ -n "${K3S_URL:-}" ]]; then
        curl -sfL https://get.k3s.io | K3S_URL="${K3S_URL}" K3S_TOKEN="${K3S_TOKEN:-}" sh -
    else
        curl -sfL https://get.k3s.io | sh -
    fi
else
    log "k3s already installed"
fi

# Beat BOINC to the CPU when both are runnable. Idle-class BOINC drop-in
# is the other half of this.
if systemctl list-unit-files k3s.service >/dev/null 2>&1; then
    ensure_systemd_dropin k3s.service prefer-over-boinc $'[Service]\nCPUWeight=500\nIOWeight=200\n'
    enable_service k3s.service
fi
