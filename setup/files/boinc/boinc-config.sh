#!/usr/bin/env bash
# Attach this host to Science United using
# ~/.config/dot-files/boinc-rpc.password.
# Point global_prefs_override.xml at setup/files/boinc/prefs/<role>.xml.
# science_united_user must be the Science United email address.
# Installed on PATH as /usr/local/bin/boinc-config.

set -euo pipefail

OWNER="${SUDO_USER:-${DOTFILES_USER:-dragon}}"
BOINC_DIR="${BOINC_DIR:-/home/${OWNER}/.local/share/boinc}"
BOINC_HOST="${BOINC_HOST:-127.0.0.1}"
BOINCCMD="${BOINCCMD:-/usr/local/bin/boinccmd}"
RPC_AUTH_FILE="${BOINC_DIR}/gui_rpc_auth.cfg"
SECRET="${BOINC_SECRET:-/home/${OWNER}/.config/dot-files/boinc-rpc.password}"
ROLE_FILE="${BOINC_ROLE_FILE:-/home/${OWNER}/.config/dot-files/role}"
ROOT_FILE="${DOTFILES_ROOT_FILE:-/home/${OWNER}/.config/dot-files/root}"
PROJECT_URL="https://scienceunited.org/"

rpc_password=""
science_united_user=""
science_united_password=""

boinc_service_active() {
    systemctl --user is-active --quiet boinc-client.service 2>/dev/null \
        || systemctl is-active --quiet boinc-client.service 2>/dev/null
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

link_boinc_prefs() {
    local role repo src dest
    role="$(boinc_role)"
    repo="$(dotfiles_root)" || return 1
    src="${repo}/setup/files/boinc/prefs/${role}.xml"
    [[ -f "$src" ]] || return 1
    dest="${BOINC_DIR}/global_prefs_override.xml"
    mkdir -p "$BOINC_DIR"
    ln -sfn "$src" "$dest"
    printf '%s\n' "$src"
}

load_secret_file() {
    local path="$1"
    [[ -f "$path" ]] || return 1
    if grep -q '=' "$path"; then
        while IFS='=' read -r key value || [[ -n "${key:-}" ]]; do
            [[ -z "$key" || "$key" == \#* ]] && continue
            key="${key%"${key##*[![:space:]]}"}"
            key="${key#"${key%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"
            value="${value#"${value%%[![:space:]]*}"}"
            case "$key" in
                rpc_password) rpc_password="$value" ;;
                science_united_user) science_united_user="$value" ;;
                science_united_password) science_united_password="$value" ;;
            esac
        done <"$path"
    else
        rpc_password="$(tr -d '[:space:]' <"$path")"
    fi
}

apply_role_prefs() {
    local role prefs_src
    role="$(boinc_role)"
    if ! prefs_src="$(link_boinc_prefs)"; then
        printf 'error: no prefs XML for role %s in the dot-files repo\n' "$role" >&2
        return 1
    fi
    printf 'applying %s prefs from %s\n' "$role" "$prefs_src"
    "$BOINCCMD" --host "$BOINC_HOST" --passwd "$rpc_password" \
        --read_global_prefs_override
}

attached_to_science_united() {
    timeout 8 "$BOINCCMD" --host "$BOINC_HOST" --passwd "$rpc_password" --acct_mgr info 2>/dev/null \
        | grep -q "$PROJECT_URL"
}

if [[ ! -x "$BOINCCMD" ]]; then
    printf 'error: %s is missing; rebuild BOINC with setup/modules/install-boinc.sh\n' "$BOINCCMD" >&2
    exit 1
fi

if ! boinc_service_active; then
    printf 'error: boinc-client user service is not running\n' >&2
    printf '       systemctl --user status boinc-client.service\n' >&2
    exit 1
fi

if [[ ! -f "$RPC_AUTH_FILE" ]]; then
    printf 'error: %s is missing; re-run install-boinc\n' "$RPC_AUTH_FILE" >&2
    exit 1
fi

load_secret_file "$SECRET" || true
if [[ -z "$rpc_password" ]]; then
    rpc_password="$(tr -d '[:space:]' <"$RPC_AUTH_FILE")"
fi
[[ -n "$rpc_password" ]] || { printf 'error: empty RPC password\n' >&2; exit 1; }

if ! wait_for_boinc_rpc; then
    printf 'error: boinc GUI RPC is not listening on %s:31416\n' "$BOINC_HOST" >&2
    systemctl --user --no-pager --full status boinc-client.service >&2 || true
    exit 1
fi

apply_role_prefs

if attached_to_science_united; then
    printf 'already attached to Science United\n'
    if [[ "${BOINC_REPLACE:-0}" != "1" ]]; then
        exit 0
    fi
    printf 'detaching existing Science United account manager\n'
    "$BOINCCMD" --host "$BOINC_HOST" --passwd "$rpc_password" --acct_mgr detach || true
    sleep 2
fi

if [[ -z "$science_united_user" || -z "$science_united_password" ]]; then
    printf 'warning: set science_united_user (email) and science_united_password in %s\n' "$SECRET" >&2
    printf '         role prefs were applied; Science United attach skipped\n' >&2
    exit 0
fi

printf 'attaching to Science United as %s\n' "$science_united_user"
attach_out=""
attach_out="$("$BOINCCMD" --host "$BOINC_HOST" --passwd "$rpc_password" \
    --acct_mgr attach "$PROJECT_URL" "$science_united_user" "$science_united_password" 2>&1 || true)"
printf '%s\n' "$attach_out"

tries=0
while ! attached_to_science_united; do
    tries=$((tries + 1))
    if [[ "$tries" -gt 24 ]]; then
        printf 'error: Science United attach did not finish after polling\n' >&2
        printf '       last client output:\n%s\n' "$attach_out" >&2
        exit 1
    fi
    sleep 5
    attach_out="$("$BOINCCMD" --host "$BOINC_HOST" --passwd "$rpc_password" \
        --acct_mgr attach "$PROJECT_URL" "$science_united_user" "$science_united_password" 2>&1 || true)"
    printf 'poll %s: %s\n' "$tries" "$(printf '%s\n' "$attach_out" | tail -n1)"
done

printf 'attached to Science United\n'
