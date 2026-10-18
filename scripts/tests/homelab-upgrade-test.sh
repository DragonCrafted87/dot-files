#!/usr/bin/env bash
# homelab-upgrade fast-forwards a clean main checkout and names the
# role walk. A dirty tree and a non-main branch are left in place.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bashrc="$(cd "${HERE}/../.." && pwd)/bashrc.d/homelab.bashrc"

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

# shellcheck disable=SC1090
source "$bashrc"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export GIT_AUTHOR_NAME=fixture
export GIT_AUTHOR_EMAIL=fixture@example.com
export GIT_COMMITTER_NAME=fixture
export GIT_COMMITTER_EMAIL=fixture@example.com

init_repo() {
    local path="$1"
    git init -b main "$path" >/dev/null
    printf 'base\n' >"${path}/marker"
    git -C "$path" add marker
    git -C "$path" commit -m base >/dev/null
}

root="${work}/homelab"
init_repo "$root"
mkdir -p "${root}/control" "${root}/machine-setup/setup/control" \
    "${root}/dot-files" "${root}/images"
printf 'inventory\n' >"${root}/control/inventory.conf"
printf 'print("fabric")\n' >"${root}/machine-setup/setup/control/fabric.py"
init_repo "${root}/images"
git -C "$root" config -f .gitmodules submodule.images.path images
git -C "$root" config -f .gitmodules submodule.dot-files.path dot-files
git -C "$root" add .gitmodules control/inventory.conf \
    machine-setup/setup/control/fabric.py
git -C "$root" update-index --add --cacheinfo \
    "160000,$(git -C "${root}/images" rev-parse HEAD),images"
git -C "$root" commit -m parent >/dev/null

export HOME="${work}/home"
mkdir -p "$HOME"
out="$(HOMELAB_ROOT="$root" homelab-upgrade --dry-run)"
grep -F "would git -C ${root} pull --ff-only" <<<"$out" >/dev/null \
    || fail "dry-run missed the parent pull: ${out}"
grep -F "would git -C ${root}/images pull --ff-only" <<<"$out" >/dev/null \
    || fail "dry-run missed the clean submodule: ${out}"
grep -F "skip ${root}/dot-files (not a checkout)" <<<"$out" >/dev/null \
    || fail "dry-run missed the missing submodule: ${out}"
grep -F "would update-role" <<<"$out" >/dev/null \
    || fail "dry-run missed update-role: ${out}"
grep -F "would python3 ${root}/machine-setup/setup/control/fabric.py --inventory ${root}/control/inventory.conf apply" <<<"$out" >/dev/null \
    || fail "dry-run missed the walk: ${out}"
[[ "$(git -C "$root" status --porcelain)" == "" ]] \
    || fail "dry-run changed the parent"

printf 'dirty\n' >>"${root}/images/marker"
out="$(HOMELAB_ROOT="$root" homelab-upgrade --dry-run)"
grep -F "skip ${root}/images (dirty)" <<<"$out" >/dev/null \
    || fail "dirty submodule was not skipped: ${out}"
grep -F "would git -C ${root}/images pull --ff-only" <<<"$out" \
    && fail "dirty submodule was pulled: ${out}"

git -C "${root}/images" checkout -- marker
git -C "${root}/images" checkout -b side
out="$(HOMELAB_ROOT="$root" homelab-upgrade --dry-run)"
grep -F "skip ${root}/images (on side)" <<<"$out" >/dev/null \
    || fail "side branch was not skipped: ${out}"

if HOMELAB_ROOT="$root" homelab-upgrade --nope >/dev/null 2>"${work}/err"; then
    fail "bad flag was accepted"
fi
grep -F 'usage: homelab-upgrade [--dry-run]' "${work}/err" >/dev/null \
    || fail "usage was not printed"

printf '%s\n' "homelab-upgrade ok"
