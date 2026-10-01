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

printf 'ok\n'
