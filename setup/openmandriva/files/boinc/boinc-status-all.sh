#!/usr/bin/env bash
# Query every host in /etc/boinc-client/hosts.list over GUI RPC.
# Uses the shared password from /var/lib/boinc/gui_rpc_auth.cfg.
#   sudo /usr/local/bin/boinc-status-all.sh

set -euo pipefail

# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/find-"$BOINCCMD".sh"

HOSTS_FILE="${HOSTS_FILE:-/etc/boinc-client/hosts.list}"
BOINC_DIR="${BOINC_DIR:-/var/lib/boinc}"
[[ -d /var/lib/boinc-client ]] && BOINC_DIR="/var/lib/boinc-client"
RPC_AUTH_FILE="${BOINC_DIR}/gui_rpc_auth.cfg"

if [[ "$(id -u)" -ne 0 ]]; then
    printf 'error: run with sudo so the RPC password is readable\n' >&2
    exit 1
fi

if [[ ! -f "$HOSTS_FILE" ]]; then
    printf 'error: %s is missing; edit setup/openmandriva/files/boinc/hosts.list\n' "$HOSTS_FILE" >&2
    exit 1
fi

if [[ ! -f "$RPC_AUTH_FILE" ]]; then
    printf 'error: %s is missing\n' "$RPC_AUTH_FILE" >&2
    exit 1
fi

RPC_PASSWORD="$(tr -d '[:space:]' <"$RPC_AUTH_FILE")"

while IFS= read -r host || [[ -n "${host:-}" ]]; do
    [[ -z "$host" || "$host" == \#* ]] && continue
    printf '==> %s\n' "$host"
    if ! "$BOINCCMD" --host "$host" --passwd "$RPC_PASSWORD" --get_host_info >/dev/null 2>&1; then
        printf '    unreachable\n'
        continue
    fi
    "$BOINCCMD" --host "$host" --passwd "$RPC_PASSWORD" --get_project_status 2>/dev/null \
        | grep "master URL" | sed 's/.*master URL: /    project: /' || printf '    no projects\n'
    task_count="$("$BOINCCMD" --host "$host" --passwd "$RPC_PASSWORD" --get_tasks 2>/dev/null \
        | grep -c "name:" || true)"
    printf '    tasks: %s\n' "$task_count"
done <"$HOSTS_FILE"
