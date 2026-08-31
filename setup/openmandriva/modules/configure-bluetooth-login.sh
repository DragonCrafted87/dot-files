#!/usr/bin/env bash
# Bring Bluetooth up before ly so an already-paired keyboard works
# on the login screen.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

ensure_packages bluez
enable_service bluetooth.service

if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
    run sudo systemctl start bluetooth.service || true
    if command -v rfkill >/dev/null; then
        run sudo rfkill unblock bluetooth || true
    fi
fi

main_conf="/etc/bluetooth/main.conf"
if [[ -f "$main_conf" ]]; then
    if grep -qE '^AutoEnable=' "$main_conf"; then
        if ! grep -qE '^AutoEnable=true' "$main_conf"; then
            log "AutoEnable=true in ${main_conf}"
            if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
                sudo sed -i -E 's/^AutoEnable=.*/AutoEnable=true/' "$main_conf"
            fi
        fi
    else
        log "add AutoEnable=true to ${main_conf}"
        if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
            printf '\n[Policy]\nAutoEnable=true\n' | sudo tee -a "$main_conf" >/dev/null
        fi
    fi
fi

ensure_systemd_dropin ly.service bluetooth $'[Unit]\nWants=bluetooth.service\nAfter=bluetooth.service\n'

if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
    run sudo systemctl daemon-reload
    if systemctl is-enabled --quiet ly.service 2>/dev/null; then
        run sudo systemctl restart ly.service || true
    fi
fi
