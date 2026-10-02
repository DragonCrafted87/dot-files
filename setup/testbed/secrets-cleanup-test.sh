#!/usr/bin/env bash
# A failing command still removes secrets copied in for that command.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="${repo}/setup/testbed/container.sh"
home="$(mktemp -d)"
list="$(mktemp)"
trap 'rm -rf "$home"; rm -f "$list"' EXIT

printf 'secret\n' >"${home}/.smbcredentials"
printf '.smbcredentials\n' >"$list"

set +e
HOME="$home" DOTFILES_TESTBED_SECRETS_LIST="$list" \
    "$script" --secrets exec false
rc=$?
set -e
[[ "$rc" -ne 0 ]] || {
    printf 'expected a non-zero status from false\n' >&2
    exit 1
}
docker exec dotfiles-testbed test ! -e /home/dragon/.smbcredentials
printf 'ok\n'
