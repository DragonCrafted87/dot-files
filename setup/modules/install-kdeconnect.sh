#!/usr/bin/env bash
# Phone Link-style SMS/clipboard/notifications via KDE Connect.
# Pairing and GrapheneOS steps live in files/kdeconnect/README.md.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

# Rock kdeconnect-sms is still Qt5 / Kirigami.2. SMS QML needs
# qt5-qtmultimedia. Names need kpeoplevcard. Dark chrome needs Breeze
# plus qqc2-desktop-style reading ~/.config/kdeglobals.
ensure_packages \
    kdeconnect \
    android-tools \
    qt5-qtmultimedia \
    kpeoplevcard \
    kpeople \
    breeze \
    breeze-icons \
    qqc2-desktop-style \
    kf6-qqc2-desktop-style \
    lib64Qt6Multimedia \
    kirigami-addons

ensure_symlink "${CONFIG_SOURCE_DIR}/kdeglobals" "${CONFIG_TARGET_DIR}/kdeglobals"

install_android_udev() {
    local src="${SETUP_FILES_DIR}/kdeconnect/51-android.rules"
    local dest="/etc/udev/rules.d/51-android.rules"

    if [[ ! -f "$src" ]]; then
        warn "missing ${src}"
        return 0
    fi
    if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
        :
    else
        log "udev ${dest}"
        run sudo install -m 0644 "$src" "$dest"
        run sudo udevadm control --reload-rules
        run sudo udevadm trigger --subsystem-match=usb || true
    fi

    if getent group plugdev >/dev/null; then
        if ! id -nG "${DOTFILES_USER}" | grep -qw plugdev; then
            log "add ${DOTFILES_USER} to plugdev"
            run sudo gpasswd -a "${DOTFILES_USER}" plugdev
        fi
    fi
}

allow_kdeconnect_firewall() {
    if ! command -v firewall-cmd >/dev/null; then
        return 0
    fi
    if ! systemctl is-active --quiet firewalld; then
        return 0
    fi

    if sudo firewall-cmd --get-services 2>/dev/null | grep -qw kdeconnect; then
        if sudo firewall-cmd --query-service=kdeconnect >/dev/null 2>&1; then
            return 0
        fi
        log "firewalld allow kdeconnect"
        run sudo firewall-cmd --permanent --add-service=kdeconnect
        run sudo firewall-cmd --reload
        return 0
    fi

    local proto
    local needed=0
    for proto in tcp udp; do
        if ! sudo firewall-cmd --query-port=1714-1764/${proto} >/dev/null 2>&1; then
            needed=1
        fi
    done
    if [[ "$needed" -eq 0 ]]; then
        return 0
    fi
    log "firewalld allow 1714-1764/tcp and 1714-1764/udp"
    run sudo firewall-cmd --permanent --add-port=1714-1764/tcp
    run sudo firewall-cmd --permanent --add-port=1714-1764/udp
    run sudo firewall-cmd --reload
}

allow_kdeconnect_firewall
install_android_udev

log "tray: kdeconnect-indicator   sms: kdeconnect-sms"
log "names need Contacts plugin on the phone plus kpeoplevcard"
log "GrapheneOS pairing notes: ${SETUP_FILES_DIR}/kdeconnect/README.md"
