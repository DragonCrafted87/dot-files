#!/usr/bin/env bash
# git-update-pre-commit-hook writes the template into the git dir git
# actually uses. A submodule's .git file stays a file.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bashrc="$(cd "${HERE}/../.." && pwd)/bashrc.d/git.bashrc"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export GIT_AUTHOR_NAME=fixture
export GIT_AUTHOR_EMAIL=fixture@example.com
export GIT_COMMITTER_NAME=fixture
export GIT_COMMITTER_EMAIL=fixture@example.com

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

# shellcheck disable=SC1090
source "$bashrc"

template="${work}/template"
mkdir -p "${template}/hooks"
cat >"${template}/hooks/pre-commit" <<'EOF'
#!/bin/sh
# fixture-hook
exit 0
EOF
chmod 0755 "${template}/hooks/pre-commit"

git_init() {
    git init -b main "$1" >/dev/null
    git -C "$1" config user.email fixture@example.com
    git -C "$1" config user.name fixture
    git -C "$1" config init.templateDir "$template"
}

hook_path() {
    local repo_dir="$1" hook_dir
    hook_dir="$(git -C "$repo_dir" rev-parse --git-path hooks)"
    if [[ "$hook_dir" != /* ]]; then
        hook_dir="${repo_dir}/${hook_dir}"
    fi
    printf '%s\n' "${hook_dir}/pre-commit"
}

origin="${work}/origin"
lab="${work}/lab"
git_init "$origin"
printf 'child\n' >"${origin}/README"
git -C "$origin" add README
git -C "$origin" commit -m child >/dev/null

git_init "$lab"
git -C "$lab" config protocol.file.allow always
git -C "$lab" -c protocol.file.allow=always submodule add "$origin" child >/dev/null
rm -f "$(hook_path "${lab}/child")"
rm -f "$(hook_path "$lab")"
git -C "${lab}/child" config init.templateDir "$template"

(
    cd "${lab}/child"
    git-update-pre-commit-hook
)
dest="$(hook_path "${lab}/child")"
[[ -x "$dest" ]] || fail "submodule hook missing at ${dest}"
cmp -s "${template}/hooks/pre-commit" "$dest" || fail "submodule hook content differs"
[[ -f "${lab}/child/.git" && ! -d "${lab}/child/.git" ]] || fail "submodule .git is no longer a file"

git -C "${lab}/child" worktree add -b side "${work}/side" HEAD >/dev/null
rm -f "$(hook_path "${work}/side")"
(
    cd "${work}/side"
    git-update-pre-commit-hook
)
side="$(hook_path "${work}/side")"
[[ -x "$side" ]] || fail "worktree hook missing at ${side}"
cmp -s "${template}/hooks/pre-commit" "$side" || fail "worktree hook content differs"

printf 'pre-commit hook path ok\n'
