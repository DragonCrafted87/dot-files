#!/usr/bin/env bash
# Local BOINC status.
# Installed on PATH as /usr/local/bin/boinc-status.

set -euo pipefail

OWNER="${SUDO_USER:-${DOTFILES_USER:-dragon}}"
BOINC_DIR="${BOINC_DIR:-/home/${OWNER}/.local/share/boinc}"
BOINC_HOST="${BOINC_HOST:-127.0.0.1}"
BOINCCMD="${BOINCCMD:-/usr/local/bin/boinccmd}"
RPC_AUTH_FILE="${BOINC_DIR}/gui_rpc_auth.cfg"

boinc_service_active() {
    systemctl --user is-active --quiet boinc-client.service 2>/dev/null \
        || systemctl is-active --quiet boinc-client.service 2>/dev/null
}

boinc_cmd() {
    timeout 8 "$BOINCCMD" --host "$BOINC_HOST" "$@"
}

if [[ ! -x "$BOINCCMD" ]]; then
    printf 'error: %s is missing; rebuild BOINC with setup/modules/compute/install-boinc.sh\n' "$BOINCCMD" >&2
    exit 1
fi

if ! boinc_service_active; then
    printf 'BOINC service: not running\n'
    exit 1
fi
printf 'BOINC service: running\n'

if [[ ! -f "$RPC_AUTH_FILE" ]]; then
    printf 'error: %s is missing\n' "$RPC_AUTH_FILE" >&2
    exit 1
fi

RPC_PASSWORD="$(tr -d '[:space:]' <"$RPC_AUTH_FILE")"

printf 'account manager:\n'
boinc_cmd --passwd "$RPC_PASSWORD" --acct_mgr info 2>/dev/null | sed 's/^/  /' || printf '  unavailable\n'

printf 'projects:\n'
PROJECT_STATUS="$(boinc_cmd --passwd "$RPC_PASSWORD" --get_project_status 2>/dev/null || true)"
if [[ -z "$PROJECT_STATUS" ]] || printf '%s\n' "$PROJECT_STATUS" | grep -q "no projects"; then
    printf '  none attached\n'
else
    printf '%s\n' "$PROJECT_STATUS" | grep "master URL" | sed 's/.*master URL: /  - /' || printf '  none attached\n'
fi

printf 'tasks:\n'
TASK_STATUS="$(boinc_cmd --passwd "$RPC_PASSWORD" --get_tasks 2>/dev/null || true)"
if [[ -z "$TASK_STATUS" ]] || printf '%s\n' "$TASK_STATUS" | grep -q "no active tasks"; then
    printf '  none active\n'
else
    if printf '%s\n' "$TASK_STATUS" | grep -q "name:"; then
        printf '%s\n' "$TASK_STATUS" | grep "name:" | sed 's/.*name: /  - /'
    else
        printf '  none active\n'
    fi
fi
