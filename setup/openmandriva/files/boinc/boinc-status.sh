#!/usr/bin/env bash
# Local BOINC status. Run with sudo so the RPC password is readable.
#   sudo /usr/local/bin/boinc-status.sh

set -euo pipefail

BOINC_DIR="${BOINC_DIR:-/var/lib/boinc}"
[[ -d /var/lib/boinc-client ]] && BOINC_DIR="/var/lib/boinc-client"
RPC_AUTH_FILE="${BOINC_DIR}/gui_rpc_auth.cfg"

if [[ "$(id -u)" -ne 0 ]]; then
    printf 'error: run with sudo so %s is readable\n' "$RPC_AUTH_FILE" >&2
    exit 1
fi

if ! systemctl is-active --quiet boinc-client; then
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
boinccmd --passwd "$RPC_PASSWORD" --acct_mgr info 2>/dev/null | sed 's/^/  /' || printf '  unavailable\n'

printf 'projects:\n'
if PROJECT_STATUS="$(boinccmd --passwd "$RPC_PASSWORD" --get_project_status 2>/dev/null)"; then
    if [[ -z "$PROJECT_STATUS" ]] || printf '%s\n' "$PROJECT_STATUS" | grep -q "no projects"; then
        printf '  none attached\n'
    else
        printf '%s\n' "$PROJECT_STATUS" | grep "master URL" | sed 's/.*master URL: /  - /'
    fi
else
    printf '  failed to query\n'
fi

printf 'tasks:\n'
if TASK_STATUS="$(boinccmd --passwd "$RPC_PASSWORD" --get_tasks 2>/dev/null)"; then
    if [[ -z "$TASK_STATUS" ]] || printf '%s\n' "$TASK_STATUS" | grep -q "no active tasks"; then
        printf '  none active\n'
    else
        printf '%s\n' "$TASK_STATUS" | grep "name:" | sed 's/.*name: /  - /'
    fi
else
    printf '  failed to query\n'
fi
