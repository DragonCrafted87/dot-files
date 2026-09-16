#!/usr/bin/env bash
# Xbox Elite Series 2 over the official wireless dongle (and USB).
# The dongle is not a standard xpad device; it needs the xone kernel
# driver plus firmware extracted from Microsoft's Windows package.
# Bluetooth paddles/profiles use xpadneo when that stack is wanted.
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

XONE_DIR="${XONE_DIR:-${DOTFILES_HOME}/src/xone}"
XPADNEO_DIR="${XPADNEO_DIR:-${DOTFILES_HOME}/src/xpadneo}"
XONE_URL="${XONE_URL:-https://github.com/medusalix/xone.git}"
XPADNEO_URL="${XPADNEO_URL:-https://github.com/atar-axis/xpadneo.git}"

install_build_deps() {
    local pkgs=(dkms curl cabextract git gcc make)
    local extra cand
    for cand in kernel-devel "kernel-devel-$(uname -r)" kernel-headers; do
        if rpm -q "$cand" >/dev/null 2>&1 || dnf list --available "$cand" >/dev/null 2>&1; then
            extra+=("$cand")
        fi
    done
    if dnf list --available steam-devices >/dev/null 2>&1 || rpm -q steam-devices >/dev/null 2>&1; then
        extra+=(steam-devices)
    fi
    ensure_packages "${pkgs[@]}" "${extra[@]}"
}

ensure_input_groups() {
    local grp
    for grp in input plugdev; do
        getent group "$grp" >/dev/null || continue
        if ! id -nG "${DOTFILES_USER}" | grep -qw "$grp"; then
            log "add ${DOTFILES_USER} to ${grp}"
            run sudo usermod -aG "$grp" "${DOTFILES_USER}"
        fi
    done
}

install_xone() {
    ensure_dir "$(dirname "$XONE_DIR")"
    ensure_repo "$XONE_URL" "$XONE_DIR"
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        return 0
    fi
    if ! lsmod | awk '{print $1}' | grep -qx xone_gip && [[ ! -d /var/lib/dkms/xone ]]; then
        log "install xone dkms"
        run sudo "${XONE_DIR}/install.sh" --release
    else
        log "xone already present"
    fi
    if [[ ! -f /lib/firmware/xow_dongle.bin && ! -f /usr/lib/firmware/xow_dongle.bin ]]; then
        log "fetch Xbox wireless dongle firmware"
        if [[ -x /usr/local/bin/xone-get-firmware.sh ]]; then
            run sudo /usr/local/bin/xone-get-firmware.sh --skip-disclaimer
        elif [[ -x "${XONE_DIR}/install/firmware.sh" ]]; then
            run sudo "${XONE_DIR}/install/firmware.sh" --skip-disclaimer
        else
            warn "xone-get-firmware.sh not found; plug the dongle after running it by hand"
        fi
    else
        log "dongle firmware already installed"
    fi
}

install_xpadneo() {
    [[ "${XBOX_INSTALL_XPADNEO:-1}" == "1" ]] || return 0
    ensure_dir "$(dirname "$XPADNEO_DIR")"
    ensure_repo "$XPADNEO_URL" "$XPADNEO_DIR"
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        return 0
    fi
    if [[ -d /var/lib/dkms/xpadneo ]] || lsmod | awk '{print $1}' | grep -qx hid_xpadneo; then
        log "xpadneo already present"
        return 0
    fi
    if [[ -x "${XPADNEO_DIR}/install.sh" ]]; then
        log "install xpadneo (Bluetooth Elite paddles / profiles)"
        run sudo "${XPADNEO_DIR}/install.sh"
    fi
}

install_build_deps
ensure_input_groups
install_xone
install_xpadneo

log "Xbox controller: unplug the dongle, reboot if this was the first DKMS build,"
log "then plug the dongle in, hold the controller pair button until it blinks."
