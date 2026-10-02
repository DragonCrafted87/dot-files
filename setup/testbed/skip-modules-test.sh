#!/usr/bin/env bash
# Proves DOTFILES_SKIP_MODULES filters run_module and nothing else.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "${work}/modules"
cat >"${work}/modules/alpha.sh" <<'EOF'
#!/usr/bin/env bash
echo alpha >>"${TEST_LOG:?}"
EOF
cat >"${work}/modules/beta.sh" <<'EOF'
#!/usr/bin/env bash
echo beta >>"${TEST_LOG:?}"
EOF
chmod 0755 "${work}/modules/"*.sh

export TEST_LOG="${work}/ran"
export REPO_ROOT="$repo"
# shellcheck disable=SC1091
. "${repo}/setup/lib/lib.sh"
# lib.sh always sets SETUP_DIR to the real setup tree after source.
SETUP_DIR="$work"

: >"$TEST_LOG"
DOTFILES_SKIP_MODULES="alpha" run_module alpha
DOTFILES_SKIP_MODULES="alpha" run_module beta
got="$(cat "$TEST_LOG")"
[[ "$got" == "beta" ]] || {
    printf 'expected only beta, got:\n%s\n' "$got" >&2
    exit 1
}

: >"$TEST_LOG"
DOTFILES_SKIP_MODULES="" run_module alpha
DOTFILES_SKIP_MODULES="" run_module beta
got="$(cat "$TEST_LOG")"
[[ "$got" == $'alpha\nbeta' ]] || {
    printf 'empty skip list should run both, got:\n%s\n' "$got" >&2
    exit 1
}

: >"$TEST_LOG"
DOTFILES_SKIP_MODULES="alpha.sh, " run_module alpha
DOTFILES_SKIP_MODULES="alpha.sh, " run_module beta
got="$(cat "$TEST_LOG")"
[[ "$got" == "beta" ]] || {
    printf 'suffix and trailing comma should skip only alpha, got:\n%s\n' "$got" >&2
    exit 1
}

printf 'ok\n'
