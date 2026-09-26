#!/usr/bin/env bash
# Query every host in /etc/boinc-client/hosts.list over GUI RPC.
# Installed on PATH as /usr/local/bin/boinc-status-all.

set -euo pipefail

OWNER="${SUDO_USER:-${DOTFILES_USER:-dragon}}"
BOINC_DIR="${BOINC_DIR:-/home/${OWNER}/.local/share/boinc}"
BOINCCMD="${BOINCCMD:-/usr/local/bin/boinccmd}"
HOSTS_FILE="${HOSTS_FILE:-/etc/boinc-client/hosts.list}"
RPC_AUTH_FILE="${BOINC_DIR}/gui_rpc_auth.cfg"

if [[ ! -x "$BOINCCMD" ]]; then
    printf 'error: %s is missing; rebuild BOINC with setup/modules/compute/install-boinc.sh\n' "$BOINCCMD" >&2
    exit 1
fi

if [[ ! -f "$HOSTS_FILE" ]]; then
    printf 'error: %s is missing; edit setup/files/boinc/hosts.list\n' "$HOSTS_FILE" >&2
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
