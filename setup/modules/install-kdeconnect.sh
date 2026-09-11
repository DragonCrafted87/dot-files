#!/usr/bin/env bash
# Phone Link-style SMS/clipboard/notifications via KDE Connect.
# Pairing and GrapheneOS steps live in files/kdeconnect/README.md.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

# Rock kdeconnect-sms still resolves Kirigami.2 from /usr/lib64/qt5/qml.
# QtMultimedia QML for that stack is qt5-qtmultimedia, not lib64Qt6Multimedia.
# Do not set QML_IMPORT_PATH to /usr/lib64/qt6/qml or Qt5 Kirigami mixes with
# Qt6 QtQml and the SMS window never appears.
ensure_packages \
    kdeconnect \
    android-tools \
    qt5-qtmultimedia \
    lib64Qt6Multimedia \
    kirigami-addons \
    kf6-qqc2-desktop-style

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

log "tray: kdeconnect-indicator   sms: kdeconnect-sms"
log "if SMS from the tray is silent, run kdeconnect-sms in a terminal"
log "GrapheneOS pairing notes: ${SETUP_FILES_DIR}/kdeconnect/README.md"
