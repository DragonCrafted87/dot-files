#!/usr/bin/env bash
# shellcheck shell=bash
# Resolve boinccmd after the Flatpak install.

BOINC_FLATPAK="${BOINC_FLATPAK:-edu.berkeley.BOINC}"
BOINC_DIR="${BOINC_DIR:-${DOTFILES_HOME:-/home/dragon}/.var/app/${BOINC_FLATPAK}}"
BOINC_HOST="${BOINC_HOST:-127.0.0.1}"

find_boinccmd() {
    local candidate
    if [[ -x /usr/local/bin/boinccmd ]]; then
        printf '%s\n' /usr/local/bin/boinccmd
        return 0
    fi
    for candidate in /usr/bin/boinccmd /usr/libexec/boinc/boinccmd; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    if command -v flatpak >/dev/null 2>&1 && flatpak info "$BOINC_FLATPAK" >/dev/null 2>&1; then
        printf '%s\n' /usr/local/bin/boinccmd
        return 0
    fi
    if command -v boinccmd >/dev/null 2>&1; then
        command -v boinccmd
        return 0
    fi
    return 1
}

BOINCCMD="$(find_boinccmd || true)"
if [[ -z "${BOINCCMD}" ]]; then
    printf 'error: boinccmd not found; install edu.berkeley.BOINC\n' >&2
    exit 1
fi
export PATH BOINCCMD BOINC_HOST BOINC_DIR BOINC_FLATPAK

boinc_cmd() {
    timeout 8 "$BOINCCMD" --host "$BOINC_HOST" "$@"
}

wait_for_boinc_rpc() {
    local _i
    for _i in $(seq 1 20); do
        if timeout 1 bash -c "echo >/dev/tcp/${BOINC_HOST}/31416" 2>/dev/null; then
            return 0
        fi
        sleep 1
    done
    return 1
}

boinc_service_active() {
    systemctl --user is-active --quiet boinc-client.service 2>/dev/null \
        || systemctl is-active --quiet boinc-client.service 2>/dev/null
}
