#!/usr/bin/env bash
# Install Piper/ratbagd and reset the G603 to profile 0 on USB plug-in.
# Windows G HUB on the work PC overwrites onboard profiles; ratbagctl is
# the CLI for the same daemon Piper uses.
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib.sh"

require_user

piper_pkg="$(pick_pkg piper || true)"
ratbag_pkg="$(pick_pkg ratbagd || true)"
pkgs=()
[[ -n "$piper_pkg" ]] && pkgs+=("$piper_pkg")
[[ -n "$ratbag_pkg" ]] && pkgs+=("$ratbag_pkg")
if [[ "${#pkgs[@]}" -eq 0 ]]; then
    warn "piper / ratbagd packages not found in dnf"
else
    ensure_packages "${pkgs[@]}"
fi

if systemctl list-unit-files ratbagd.service >/dev/null 2>&1; then
    enable_service ratbagd.service
    if ! systemctl is-active --quiet ratbagd.service 2>/dev/null; then
        log "start ratbagd.service"
        run sudo systemctl start ratbagd.service || true
    fi
fi

src_rules="${SETUP_FILES_DIR}/piper/99-piper-profile-reset.rules"
dest_rules="/etc/udev/rules.d/99-piper-profile-reset.rules"
if [[ -f "$src_rules" ]]; then
    if [[ -f "$dest_rules" ]] && cmp -s "$src_rules" "$dest_rules"; then
        :
    else
        log "udev ${dest_rules}"
        run sudo install -m 0644 "$src_rules" "$dest_rules"
        run sudo udevadm control --reload-rules
        run sudo udevadm trigger --subsystem-match=usb --subsystem-match=hidraw || true
    fi
else
    warn "missing ${src_rules}"
fi

src_unit="${SETUP_FILES_DIR}/piper/reset-piper-profile.service"
dest_unit="${DOTFILES_HOME}/.config/systemd/user/reset-piper-profile.service"
if [[ -f "$src_unit" ]]; then
    ensure_dir "$(dirname "$dest_unit")"
    if [[ -f "$dest_unit" ]] && cmp -s "$src_unit" "$dest_unit"; then
        :
    else
        log "user unit ${dest_unit}"
        run install -m 0644 "$src_unit" "$dest_unit"
        run systemctl --user daemon-reload || true
    fi
    enable_user_service reset-piper-profile.service
fi
