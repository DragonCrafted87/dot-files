#!/usr/bin/env bash
# down uses the same guest poweroff, then virsh destroy, path as seal.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
. "${repo}/setup/testbed/vm.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
log="${work}/log"

ssh_guest() {
    printf 'ssh %s\n' "$*" >>"$log"
    return 0
}

sudo() {
    printf 'sudo %s\n' "$*" >>"$log"
    return 0
}

sleep() { :; }

wait_shutoff() {
    printf 'wait %s\n' "$1" >>"$log"
    return 0
}

domain_state() {
    printf 'running\n'
}

: >"$log"
cmd_down
grep -F 'systemctl poweroff' "$log" >/dev/null || {
    printf 'down did not request a guest poweroff\n' >&2
    exit 1
}
grep -F "virsh destroy ${CLONE_NAME}" "$log" >/dev/null || {
    printf 'down did not destroy a domain that stayed up\n' >&2
    exit 1
}
grep -F "wait ${CLONE_NAME}" "$log" >/dev/null || {
    printf 'down did not wait for shutoff\n' >&2
    exit 1
}

: >"$log"
domain_state() { printf 'shut off\n'; }
cmd_down
if grep -F 'virsh destroy' "$log" >/dev/null; then
    printf 'down destroyed a domain that was already shut off\n' >&2
    exit 1
fi

: >"$log"
domain_state() { printf 'absent\n'; }
cmd_down
if grep -F 'virsh destroy' "$log" >/dev/null; then
    printf 'down destroyed an absent domain\n' >&2
    exit 1
fi

declare -f cmd_seal | grep -F 'power_off_domain' >/dev/null || {
    printf 'seal does not use power_off_domain\n' >&2
    exit 1
}

printf 'ok\n'
