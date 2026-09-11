#!/usr/bin/env bash
# Local BOINC status.
#   /usr/local/bin/boinc-status.sh

set -euo pipefail

# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/find-boinccmd.sh"

OWNER="${SUDO_USER:-${DOTFILES_USER:-dragon}}"
BOINC_DIR="${BOINC_DIR:-/home/${OWNER}/.var/app/edu.berkeley.BOINC}"
RPC_AUTH_FILE="${BOINC_DIR}/gui_rpc_auth.cfg"

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
