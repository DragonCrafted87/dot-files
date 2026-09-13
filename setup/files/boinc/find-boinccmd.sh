#!/usr/bin/env bash
# shellcheck shell=bash
# Resolve boinccmd after the Flatpak install.

BOINC_FLATPAK="${BOINC_FLATPAK:-edu.berkeley.BOINC}"
OWNER="${SUDO_USER:-${DOTFILES_USER:-dragon}}"
BOINC_DIR="${BOINC_DIR:-${DOTFILES_HOME:-/home/${OWNER}}/.var/app/${BOINC_FLATPAK}}"
BOINC_HOST="${BOINC_HOST:-127.0.0.1}"
ROLE_FILE="${BOINC_ROLE_FILE:-/home/${OWNER}/.config/dot-files/role}"
ROOT_FILE="${DOTFILES_ROOT_FILE:-/home/${OWNER}/.config/dot-files/root}"

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

dotfiles_root() {
    local path
    if [[ -n "${DOTFILES_ROOT:-}" && -d "$DOTFILES_ROOT/setup/files/boinc/prefs" ]]; then
        printf '%s\n' "$DOTFILES_ROOT"
        return 0
    fi
    if [[ -f "$ROOT_FILE" ]]; then
        path="$(tr -d '[:space:]' <"$ROOT_FILE")"
        if [[ -n "$path" && -d "$path/setup/files/boinc/prefs" ]]; then
            printf '%s\n' "$path"
            return 0
        fi
    fi
    path="/home/${OWNER}/dot-files"
    if [[ -d "$path/setup/files/boinc/prefs" ]]; then
        printf '%s\n' "$path"
        return 0
    fi
    return 1
}

boinc_role() {
    local role="${BOINC_ROLE:-${OMV_ROLE:-}}"
    if [[ -z "$role" && -f "$ROLE_FILE" ]]; then
        role="$(tr -d '[:space:]' <"$ROLE_FILE")"
    fi
    printf '%s\n' "${role:-server}"
}

boinc_prefs_src() {
    local mode="${1:-active}"
    local role repo candidate
    role="$(boinc_role)"
    repo="$(dotfiles_root)" || return 1
    if [[ "$mode" == idle ]]; then
        candidate="${repo}/setup/files/boinc/prefs/${role}-idle.xml"
        if [[ -f "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    fi
    candidate="${repo}/setup/files/boinc/prefs/${role}.xml"
    [[ -f "$candidate" ]] || return 1
    printf '%s\n' "$candidate"
}

copy_boinc_prefs() {
    local mode="${1:-active}"
    local src dest
    src="$(boinc_prefs_src "$mode")" || return 1
    dest="${BOINC_DIR}/global_prefs_override.xml"
    mkdir -p "$BOINC_DIR"
    cp -f "$src" "$dest"
    printf '%s\n' "$src"
}
