#!/usr/bin/env bash
# ensure_repo accepts an injected checkout that git cannot see.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
unset REPO_ROOT DOTFILES_ROOT DOTFILES_LIB_LOADED
# shellcheck disable=SC1091
. "${HERE}/../lib/lib.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "${work}/checkout/setup"
printf '%s\n' '#!/usr/bin/env bash' >"${work}/checkout/setup/role.sh"
ensure_repo "git@example.invalid:no/such.git" "${work}/checkout"

mkdir -p "${work}/empty-dir"
set +e
(
    ensure_repo "git@example.invalid:no/such.git" "${work}/empty-dir" \
        >/tmp/ensure-repo-empty.out 2>/tmp/ensure-repo-empty.err
)
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
    printf 'empty directory was accepted as a checkout\n' >&2
    exit 1
fi
if ! grep -F 'not a git repository' /tmp/ensure-repo-empty.err >/dev/null; then
    printf 'empty directory failed without the git error\n' >&2
    exit 1
fi

echo ok
