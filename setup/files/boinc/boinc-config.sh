#!/usr/bin/env bash
# Attach this host to Science United using
# ~/.config/dot-files/boinc-rpc.password.
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

if "$BOINCCMD" --host "$BOINC_HOST" --passwd "$rpc_password" --acct_mgr info 2>/dev/null | grep -q "$PROJECT_URL"; then
    printf 'already attached to Science United\n'
    if [[ "${BOINC_REPLACE:-0}" != "1" ]]; then
        exit 0
    fi
    printf 'detaching existing Science United account manager\n'
    "$BOINCCMD" --host "$BOINC_HOST" --passwd "$rpc_password" --acct_mgr detach
fi

if [[ -z "$science_united_user" || -z "$science_united_password" ]]; then
    printf 'error: set science_united_user (email) and science_united_password in %s\n' "$SECRET" >&2
    exit 1
fi

printf 'attaching to Science United as %s\n' "$science_united_user"
if ! timeout 60 "$BOINCCMD" --host "$BOINC_HOST" --passwd "$rpc_password" \
        --acct_mgr attach "$PROJECT_URL" "$science_united_user" "$science_united_password"; then
    printf 'warning: attach timed out or Science United HTTP failed\n' >&2
    printf '          retry later: /usr/local/bin/boinc-config.sh\n' >&2
    exit 1
fi

sleep 2
if timeout 8 "$BOINCCMD" --host "$BOINC_HOST" --passwd "$rpc_password" --acct_mgr info 2>/dev/null | grep -q "$PROJECT_URL"; then
    printf 'attached to Science United\n'
else
    printf 'warning: attach did not verify; retry with /usr/local/bin/boinc-config.sh\n' >&2
    exit 1
fi
