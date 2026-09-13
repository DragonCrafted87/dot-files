#!/usr/bin/env bash
# Attach this host to Science United using
# ~/.config/dot-files/boinc-rpc.password.
# Re-apply files/boinc/prefs/<role>.xml as global_prefs_override.xml.
# science_united_user must be the Science United email address.
#   /usr/local/bin/boinc-config.sh

set -euo pipefail

# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/find-boinccmd.sh"

PROJECT_URL="https://scienceunited.org/"
OWNER="${SUDO_USER:-${DOTFILES_USER:-dragon}}"
BOINC_DIR="${BOINC_DIR:-/home/${OWNER}/.var/app/edu.berkeley.BOINC}"
RPC_AUTH_FILE="${BOINC_DIR}/gui_rpc_auth.cfg"
SECRET="${BOINC_SECRET:-/home/${OWNER}/.config/dot-files/boinc-rpc.password}"
ROLE_FILE="${BOINC_ROLE_FILE:-/home/${OWNER}/.config/dot-files/role}"
PREFS_DEST="${BOINC_DIR}/global_prefs_override.xml"

rpc_password=""
science_united_user=""
science_united_password=""

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

resolve_role() {
    local role="${BOINC_ROLE:-${OMV_ROLE:-}}"
    if [[ -z "$role" && -f "$ROLE_FILE" ]]; then
        role="$(tr -d '[:space:]' <"$ROLE_FILE")"
    fi
    printf '%s\n' "${role:-server}"
}

resolve_prefs_src() {
    local role="$1"
    local candidate
    for candidate in \
        "${BOINC_PREFS_FILE:-}" \
        "${BOINC_PREFS_DIR:-}/${role}.xml" \
        "/etc/boinc-client/prefs/${role}.xml" \
        "/home/${OWNER}/dot-files/setup/files/boinc/prefs/${role}.xml"
    do
        [[ -n "$candidate" && -f "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done
    return 1
}

apply_role_prefs() {
    local role prefs_src
    role="$(resolve_role)"
    if ! prefs_src="$(resolve_prefs_src "$role")"; then
        printf 'error: no prefs XML for role %s\n' "$role" >&2
        printf '       expected /etc/boinc-client/prefs/%s.xml\n' "$role" >&2
        return 1
    fi
    if [[ -f "$PREFS_DEST" ]] && cmp -s "$prefs_src" "$PREFS_DEST"; then
        printf 'prefs already match %s (%s)\n' "$role" "$prefs_src"
    else
        printf 'applying %s prefs from %s\n' "$role" "$prefs_src"
        install -m 0644 "$prefs_src" "$PREFS_DEST"
    fi
    "$BOINCCMD" --host "$BOINC_HOST" --passwd "$rpc_password" \
        --read_global_prefs_override
}

attached_to_science_united() {
    timeout 8 "$BOINCCMD" --host "$BOINC_HOST" --passwd "$rpc_password" --acct_mgr info 2>/dev/null \
        | grep -q "$PROJECT_URL"
}

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
    printf 'error: set science_united_user (email) and science_united_password in %s\n' "$SECRET" >&2
    exit 1
fi

printf 'attaching to Science United as %s\n' "$science_united_user"
# acct_mgr attach is async. The first call usually prints "poll status: retry"
# and returns 0. Keep asking until info shows the URL or we time out.
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
