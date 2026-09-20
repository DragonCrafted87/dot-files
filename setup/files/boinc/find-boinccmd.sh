#!/usr/bin/env bash
# shellcheck shell=bash
# Resolve boinccmd after the source install.

OWNER="${SUDO_USER:-${DOTFILES_USER:-dragon}}"
BOINC_DIR="${BOINC_DIR:-${DOTFILES_HOME:-/home/${OWNER}}/.local/share/boinc}"
BOINC_HOST="${BOINC_HOST:-127.0.0.1}"
ROLE_FILE="${BOINC_ROLE_FILE:-/home/${OWNER}/.config/dot-files/role}"
ROOT_FILE="${DOTFILES_ROOT_FILE:-/home/${OWNER}/.config/dot-files/root}"

find_boinccmd() {
    local candidate
    for candidate in /usr/local/bin/boinccmd /usr/bin/boinccmd /usr/libexec/boinc/boinccmd; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    if command -v boinccmd >/dev/null 2>&1; then
        command -v boinccmd
        return 0
    fi
    return 1
}

BOINCCMD="$(find_boinccmd || true)"
if [[ -z "${BOINCCMD}" ]]; then
    printf 'error: boinccmd not found; rebuild BOINC with setup/modules/install-boinc.sh\n' >&2
    exit 1
fi
export PATH BOINCCMD BOINC_HOST BOINC_DIR

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
    local role repo candidate
    role="$(boinc_role)"
    repo="$(dotfiles_root)" || return 1
    candidate="${repo}/setup/files/boinc/prefs/${role}.xml"
    [[ -f "$candidate" ]] || return 1
    printf '%s\n' "$candidate"
}

link_boinc_prefs() {
    local src dest
    src="$(boinc_prefs_src)" || return 1
    dest="${BOINC_DIR}/global_prefs_override.xml"
    mkdir -p "$BOINC_DIR"
    ln -sfn "$src" "$dest"
    printf '%s\n' "$src"
}
