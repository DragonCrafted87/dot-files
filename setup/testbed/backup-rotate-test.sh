#!/usr/bin/env bash
# Backup rotation and the clone-boot guard. No libvirt required.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
. "${repo}/setup/testbed/vm.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo one >"${work}/golden.qcow2"
echo two >"${work}/src.qcow2"

if rotate_backup "${work}/src.qcow2" "${work}/missing/dot-files"; then
    printf 'missing dest should fail\n' >&2
    exit 1
fi
[[ ! -e "${work}/missing/dot-files/golden.qcow2.new" ]]
[[ "$(cat "${work}/golden.qcow2")" == "one" ]]

mkdir -p "${work}/share"
rotate_backup "${work}/src.qcow2" "${work}/share"
[[ "$(cat "${work}/share/golden.qcow2")" == "two" ]]
echo three >"${work}/src.qcow2"
rotate_backup "${work}/src.qcow2" "${work}/share"
[[ "$(cat "${work}/share/golden.qcow2")" == "three" ]]
[[ "$(cat "${work}/share/golden.qcow2.bak")" == "two" ]]

if up_allowed running "${work}/share/golden.qcow2"; then
    printf 'running golden should refuse up\n' >&2
    exit 1
fi
if up_allowed "shut off" "${work}/missing-backup"; then
    printf 'missing backup should refuse up\n' >&2
    exit 1
fi
up_allowed "shut off" "${work}/share/golden.qcow2"

refuse_up() {
    local state="$1"
    if up_allowed "$state" "${work}/share/golden.qcow2"; then
        printf 'state %q should refuse up\n' "$state" >&2
        exit 1
    fi
}
refuse_up paused
refuse_up "in shutdown"
refuse_up unknown
refuse_up ""
up_allowed absent "${work}/share/golden.qcow2"

echo src >"${work}/tiny-golden"

backup_refuses() {
    local want="$1"
    local out="${work}/backup-${want// /-}"
    mkdir -p "$out"
    set +e
    (
        GOLDEN_DISK="${work}/tiny-golden"
        BACKUP_DIR="$out"
        domain_state() { printf '%s\n' "$want"; }
        cmd_backup
    ) >/dev/null 2>&1
    local rc=$?
    set -e
    [[ "$rc" -ne 0 ]] || {
        printf 'backup allowed state %q\n' "$want" >&2
        exit 1
    }
    [[ ! -e "${out}/golden.qcow2" ]] || {
        printf 'backup wrote a copy while state was %q\n' "$want" >&2
        exit 1
    }
}
backup_refuses paused
backup_refuses "in shutdown"
backup_refuses unknown
backup_refuses ""

mkdir -p "${work}/backup-ok"
(
    GOLDEN_DISK="${work}/tiny-golden"
    BACKUP_DIR="${work}/backup-ok"
    domain_state() { printf 'shut off\n'; }
    cmd_backup
)
[[ "$(cat "${work}/backup-ok/golden.qcow2")" == "src" ]]

mkdir -p "${work}/backup-absent"
(
    GOLDEN_DISK="${work}/tiny-golden"
    BACKUP_DIR="${work}/backup-absent"
    domain_state() { printf 'absent\n'; }
    cmd_backup
)
[[ "$(cat "${work}/backup-absent/golden.qcow2")" == "src" ]]

[[ "$(classify_domstate 0 "shut off" "")" == "shut off" ]]
[[ "$(classify_domstate 1 "" "error: failed to get domain 'dotfiles-golden'")" == "absent" ]]
[[ "$(classify_domstate 1 "" "error: Cannot recv data")" == "unknown" ]]

(
    sudo() {
        printf '%s\n' "error: failed to get domain 'dotfiles-golden'" >&2
        return 1
    }
    [[ "$(domain_state "$GOLDEN_NAME")" == "absent" ]]
)
(
    sudo() {
        printf '%s\n' "error: Cannot recv data" >&2
        return 1
    }
    [[ "$(domain_state "$GOLDEN_NAME")" == "unknown" ]]
)
(
    sudo() {
        printf '%s\n' "shut off"
        return 0
    }
    [[ "$(domain_state "$GOLDEN_NAME")" == "shut off" ]]
)

: >"${work}/up-log"
(
    require_host() { :; }
    domain_state() {
        if [[ "$1" == "$GOLDEN_NAME" ]]; then
            printf 'shut off\n'
        else
            printf 'absent\n'
        fi
    }
    GOLDEN_DISK="${work}/tiny-golden"
    BACKUP_DIR="${work}/share"
    CLONE_DISK="${work}/no-such-clone.qcow2"
    sudo() {
        printf '%s\n' "$*" >>"${work}/up-log"
        return 0
    }
    cmd_up
)
grep -F 'virt-install' "${work}/up-log" >/dev/null
if grep -F 'virsh start' "${work}/up-log" >/dev/null; then
    printf 'up started a clone domain that does not exist\n' >&2
    exit 1
fi

echo overlay >"${work}/clone.qcow2"
: >"${work}/destroy-log"
(
    CLONE_DISK="${work}/clone.qcow2"
    domain_state() { printf 'absent\n'; }
    sudo() {
        if [[ "$1" == "rm" ]]; then
            shift
            rm "$@"
            return 0
        fi
        printf '%s\n' "$*" >>"${work}/destroy-log"
        return 0
    }
    cmd_destroy_clone
)
[[ ! -e "${work}/clone.qcow2" ]]
if grep -F 'virsh destroy' "${work}/destroy-log" >/dev/null; then
    printf 'destroy-clone destroyed an absent domain\n' >&2
    exit 1
fi

echo overlay >"${work}/clone-unknown.qcow2"
set +e
(
    CLONE_DISK="${work}/clone-unknown.qcow2"
    domain_state() { printf 'unknown\n'; }
    sudo() {
        if [[ "$1" == "rm" ]]; then
            shift
            rm "$@"
            return 0
        fi
        printf '%s\n' "$*" >>"${work}/destroy-unknown"
        return 0
    }
    cmd_destroy_clone
) >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]]
[[ -e "${work}/clone-unknown.qcow2" ]]

printf 'ok\n'
