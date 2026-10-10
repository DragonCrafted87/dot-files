#!/usr/bin/env bash
# update-role fast-forwards a clean machine-setup checkout. A dirty tree
# or a detached HEAD is left in place and the role still runs. A pull
# that cannot fast-forward stops before the role.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bashrc="$(cd "${HERE}/../.." && pwd)/bashrc.d/setup.bashrc"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export GIT_AUTHOR_NAME=fixture
export GIT_AUTHOR_EMAIL=fixture@example.com
export GIT_COMMITTER_NAME=fixture
export GIT_COMMITTER_EMAIL=fixture@example.com
export GIT_TERMINAL_PROMPT=0

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

# shellcheck disable=SC1090
source "$bashrc"

make_origin() {
    local origin="$1"
    git init -b main "$origin" >/dev/null
    mkdir -p "${origin}/setup"
    cat >"${origin}/setup/role.sh" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"${ROLE_LOG:?}"
exit 0
EOF
    chmod 755 "${origin}/setup/role.sh"
    printf 'base\n' >"${origin}/marker"
    git -C "$origin" add setup/role.sh marker
    git -C "$origin" commit -m base >/dev/null
}

prepare_home() {
    local home="$1"
    local setup="$2"
    mkdir -p "${home}/.config/dot-files"
    printf 'workstation\n' >"${home}/.config/dot-files/role"
    printf 'dot-files=%s\nmachine-setup=%s\n' "$setup" "$setup" \
        >"${home}/.config/dot-files/checkouts"
}

run_update() {
    local home="$1"
    shift
    local log="${home}/role.log"
    : >"$log"
    local rc=0
    set +e
    HOME="$home" ROLE_LOG="$log" update-role "$@" >"${home}/out" 2>"${home}/err"
    rc=$?
    set -e
    printf '%s\n' "$rc"
}

origin="${work}/origin"
make_origin "$origin"

# Clean and behind: fast-forward, then the role runs.
clone="${work}/clone"
git clone "$origin" "$clone" >/dev/null
printf 'next\n' >>"${origin}/marker"
git -C "$origin" add marker
git -C "$origin" commit -m next >/dev/null
home="${work}/home-ff"
prepare_home "$home" "$clone"
before="$(git -C "$clone" rev-parse HEAD)"
rc="$(run_update "$home")"
[[ "$rc" -eq 0 ]] || fail "clean pull exited ${rc}: $(cat "${home}/err") $(cat "${home}/out")"
after="$(git -C "$clone" rev-parse HEAD)"
[[ "$after" != "$before" ]] || fail "clean tree was not fast-forwarded"
[[ "$after" == "$(git -C "$origin" rev-parse HEAD)" ]] || fail "clean tree did not match origin"
grep -F 'workstation' "${home}/role.log" >/dev/null || fail "role did not run after pull"
grep -F 'git pull --ff-only' "${home}/out" >/dev/null || fail "pull was not reported"

# Dirty: leave the commit, still run the role.
clone_dirty="${work}/clone-dirty"
git clone "$origin" "$clone_dirty" >/dev/null
home_dirty="${work}/home-dirty"
prepare_home "$home_dirty" "$clone_dirty"
printf 'local\n' >"${clone_dirty}/local"
dirty_head="$(git -C "$clone_dirty" rev-parse HEAD)"
rc="$(run_update "$home_dirty")"
[[ "$rc" -eq 0 ]] || fail "dirty update exited ${rc}: $(cat "${home_dirty}/err")"
[[ "$(git -C "$clone_dirty" rev-parse HEAD)" == "$dirty_head" ]] || fail "dirty tree moved"
[[ -f "${clone_dirty}/local" ]] || fail "dirty file was removed"
grep -F 'dirty' "${home_dirty}/out" >/dev/null \
    || fail "dirty tree was not reported: $(cat "${home_dirty}/out")"
grep -F 'workstation' "${home_dirty}/role.log" >/dev/null \
    || fail "role did not run on a dirty tree"

# Detached: leave it, still run the role.
clone_det="${work}/clone-det"
git clone "$origin" "$clone_det" >/dev/null
home_det="${work}/home-det"
prepare_home "$home_det" "$clone_det"
git -C "$clone_det" checkout --detach >/dev/null
det_head="$(git -C "$clone_det" rev-parse HEAD)"
rc="$(run_update "$home_det")"
[[ "$rc" -eq 0 ]] || fail "detached update exited ${rc}: $(cat "${home_det}/err")"
[[ "$(git -C "$clone_det" rev-parse HEAD)" == "$det_head" ]] || fail "detached tree moved"
if git -C "$clone_det" symbolic-ref -q HEAD >/dev/null; then
    fail "detached tree gained a branch"
fi
grep -F 'detached HEAD' "${home_det}/out" >/dev/null \
    || fail "detached tree was not reported: $(cat "${home_det}/out")"
grep -F 'workstation' "${home_det}/role.log" >/dev/null \
    || fail "role did not run while detached"

# Diverged clean tree: the pull fails and the role does not run.
clone_div="${work}/clone-div"
git clone "$origin" "$clone_div" >/dev/null
home_div="${work}/home-div"
prepare_home "$home_div" "$clone_div"
git -C "$clone_div" commit --allow-empty -m local >/dev/null
printf 'remote\n' >"${origin}/other"
git -C "$origin" add other
git -C "$origin" commit -m remote >/dev/null
div_head="$(git -C "$clone_div" rev-parse HEAD)"
rc="$(run_update "$home_div")"
[[ "$rc" -ne 0 ]] || fail "diverged pull was accepted"
[[ "$(git -C "$clone_div" rev-parse HEAD)" == "$div_head" ]] || fail "diverged tree moved"
[[ ! -s "${home_div}/role.log" ]] || fail "role ran after a failed pull: $(cat "${home_div}/role.log")"

# Dry-run of a clean tree that is behind does not pull.
clone_dry="${work}/clone-dry"
git clone "$origin" "$clone_dry" >/dev/null
home_dry="${work}/home-dry"
prepare_home "$home_dry" "$clone_dry"
git -C "$clone_dry" reset --hard HEAD~1 >/dev/null
dry_head="$(git -C "$clone_dry" rev-parse HEAD)"
rc="$(run_update "$home_dry" --dry-run)"
[[ "$rc" -eq 0 ]] || fail "dry-run exited ${rc}: $(cat "${home_dry}/err")"
[[ "$(git -C "$clone_dry" rev-parse HEAD)" == "$dry_head" ]] || fail "dry-run pulled"
grep -F 'would git pull --ff-only' "${home_dry}/out" >/dev/null \
    || fail "dry-run did not report the pull: $(cat "${home_dry}/out")"
grep -F -- '--dry-run' "${home_dry}/role.log" >/dev/null \
    || fail "role did not see --dry-run: $(cat "${home_dry}/role.log")"

# Help does not pull.
clone_help="${work}/clone-help"
git clone "$origin" "$clone_help" >/dev/null
home_help="${work}/home-help"
prepare_home "$home_help" "$clone_help"
git -C "$clone_help" reset --hard HEAD~1 >/dev/null
help_head="$(git -C "$clone_help" rev-parse HEAD)"
rc="$(run_update "$home_help" --help)"
[[ "$rc" -eq 0 ]] || fail "help exited ${rc}: $(cat "${home_help}/err")"
[[ "$(git -C "$clone_help" rev-parse HEAD)" == "$help_head" ]] || fail "help pulled"
grep -F -- '--help' "${home_help}/role.log" >/dev/null \
    || fail "help did not reach role.sh: $(cat "${home_help}/role.log")"

# A directory that is not a git checkout stops before the role.
plain="${work}/plain-setup"
mkdir -p "${plain}/setup"
cat >"${plain}/setup/role.sh" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"${ROLE_LOG:?}"
exit 0
EOF
chmod 755 "${plain}/setup/role.sh"
home_plain="${work}/home-plain"
prepare_home "$home_plain" "$plain"
rc="$(run_update "$home_plain")"
[[ "$rc" -ne 0 ]] || fail "non-git machine-setup was accepted"
[[ ! -s "${home_plain}/role.log" ]] || fail "role ran for a non-git machine-setup"
grep -F 'not a git work tree' "${home_plain}/err" >/dev/null \
    || fail "non-git error: $(cat "${home_plain}/err") $(cat "${home_plain}/out")"

printf 'update-role pull ok\n'
