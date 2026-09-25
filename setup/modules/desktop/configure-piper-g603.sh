#!/usr/bin/env bash
# Install Piper/ratbagd and reset G603/G604 to profile 0 on USB plug-in.
# Windows G HUB on the work PC overwrites onboard profiles; ratbagctl is
# the CLI for the same daemon Piper uses.
set -euo pipefail
# shellcheck disable=SC1091
. "${REPO_ROOT:-$DOTFILES_ROOT}/setup/lib/lib.sh"

require_user

install_root_file() {
    local src="$1"
    local dest="$2"
    local mode="${3:-0644}"
    INSTALL_ROOT_FILE_WROTE=0
    if [[ ! -f "$src" ]]; then
        warn "missing ${src}"
        return 1
    fi
    if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
        return 0
    fi
    log "${dest}"
    run sudo install -m "$mode" "$src" "$dest"
    INSTALL_ROOT_FILE_WROTE=1
}

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
    ensure_systemd_dropin ratbagd.service hidraw-rescan $'[Service]\n# Replay hidraw ADD after start so Lightspeed HID++ nodes missed at boot show up.\nExecStartPost=/usr/bin/udevadm trigger --action=add --subsystem-match=hidraw\n'
    if ! systemctl is-active --quiet ratbagd.service 2>/dev/null; then
        log "start ratbagd.service"
        run sudo systemctl start ratbagd.service || true
    fi
fi

src_rules="${SETUP_FILES_DIR}/piper/99-piper-profile-reset.rules"
dest_rules="/etc/udev/rules.d/99-piper-profile-reset.rules"
if install_root_file "$src_rules" "$dest_rules" && [[ "${INSTALL_ROOT_FILE_WROTE}" -eq 1 ]]; then
    run sudo udevadm control --reload-rules
    run sudo udevadm trigger --subsystem-match=usb --subsystem-match=hid --subsystem-match=hidraw || true
fi

src_rescan="${SETUP_FILES_DIR}/piper/ratbagd-hidraw-rescan.service"
dest_rescan="/etc/systemd/system/ratbagd-hidraw-rescan.service"
if install_root_file "$src_rescan" "$dest_rescan" && [[ "${INSTALL_ROOT_FILE_WROTE}" -eq 1 ]]; then
    run sudo systemctl daemon-reload
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
