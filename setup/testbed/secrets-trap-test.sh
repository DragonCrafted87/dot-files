#!/usr/bin/env bash
# A docker cp failure still removes secrets copied earlier in the list.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
. "${repo}/setup/testbed/container.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "${work}/home"
printf 'one\n' >"${work}/home/a"
printf 'two\n' >"${work}/home/b"
printf 'a\nb\n' >"${work}/list"
: >"${work}/docker-log"
: >"${work}/removed"

cp_count=0
docker() {
    printf '%s\n' "$*" >>"${work}/docker-log"
    if [[ "$1" == "cp" ]]; then
        cp_count=$((cp_count + 1))
        [[ "$cp_count" -eq 1 ]]
        return
    fi
    if [[ "$1" == "exec" && "$*" == *" rm -f "* ]]; then
        printf '%s\n' "${*: -1}" >>"${work}/removed"
    fi
    return 0
}

HOME="${work}/home"
DOTFILES_TESTBED_SECRETS_LIST="${work}/list"
use_secrets=1
HOST_GID=1006

set +e
(
    set -euo pipefail
    run_guarded true
)
rc=$?
set -e
[[ "$rc" -ne 0 ]] || {
    printf 'expected the copy loop to fail\n' >&2
    exit 1
}
grep -F '/home/dragon/a' "${work}/removed" >/dev/null || {
    printf 'earlier secret was left after a later docker cp failed\n' >&2
    exit 1
}
grep -F 'chown dragon:1006' "${work}/docker-log" >/dev/null || {
    printf 'chown did not use the numeric host gid\n' >&2
    exit 1
}
if grep -F '/home/dragon/b' "${work}/removed" >/dev/null; then
    printf 'removed a secret whose copy failed\n' >&2
    exit 1
fi

# A failed chown still removes the file that docker cp already wrote.
: >"${work}/docker-log"
: >"${work}/removed"
cp_count=0
docker() {
    printf '%s\n' "$*" >>"${work}/docker-log"
    if [[ "$1" == "cp" ]]; then
        return 0
    fi
    if [[ "$1" == "exec" && "$*" == *"chown"* ]]; then
        return 1
    fi
    if [[ "$1" == "exec" && "$*" == *" rm -f "* ]]; then
        printf '%s\n' "${*: -1}" >>"${work}/removed"
    fi
    return 0
}
printf 'a\n' >"${work}/list"

set +e
(
    set -euo pipefail
    run_guarded true
)
rc=$?
set -e
[[ "$rc" -ne 0 ]] || {
    printf 'expected chown to fail\n' >&2
    exit 1
}
grep -F '/home/dragon/a' "${work}/removed" >/dev/null || {
    printf 'secret was left after chown failed\n' >&2
    exit 1
}

printf 'ok\n'
