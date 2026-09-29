#!/usr/bin/env bash
# State machine for the unattended role reset. No reboot, no dnf.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
continue_sh="${repo}/setup/reset-continue.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

new_plan() {
    local phase="$1" attempts="$2"
    local dir="${work}/plan-${phase}-${attempts}-$$"
    mkdir -p "$dir"
    printf '%s\n' "$phase" >"${dir}/phase"
    printf '%s\n' "$attempts" >"${dir}/attempts"
    printf 'dragon\n' >"${dir}/user"
    printf '%s\n' "$repo" >"${dir}/repo"
    printf 'workstation\n' >"${dir}/role"
    printf 'laptop\n' >"${dir}/subroles"
    printf '%s\n' "$dir"
}

run_phase() {
    local dir="$1" remove_rc="${2:-0}" install_rc="${3:-0}" early_fail="${4:-0}"
    local actions="${dir}.actions"
    : >"$actions"
    set +e
    RESET_PLAN_DIR="$dir" \
        RESET_CONTINUE_DRY_RUN=1 \
        RESET_ACTION_LOG="$actions" \
        RESET_TEST_REMOVE_RC="$remove_rc" \
        RESET_TEST_INSTALL_RC="$install_rc" \
        RESET_TEST_EARLY_FAIL="$early_fail" \
        bash "$continue_sh" >"${dir}.out" 2>"${dir}.err"
    local rc=$?
    set -e
    printf '%s\n' "$rc"
}

assert_grep() {
    grep -q "$1" "$2" || {
        printf 'missing %s in %s\n' "$1" "$2" >&2
        cat "$2" >&2
        exit 1
    }
}

# remove success -> install, attempts 0, one reboot
dir="$(new_plan remove 0)"
run_phase "$dir" >/dev/null
[[ "$(tr -d '[:space:]' <"${dir}/phase")" == install ]]
[[ "$(tr -d '[:space:]' <"${dir}/attempts")" == 0 ]]
assert_grep '^prune-remove$' "${dir}.actions"
assert_grep '^reboot$' "${dir}.actions"

# first remove failure reboots and stays on remove
dir="$(new_plan remove 0)"
run_phase "$dir" 1 >/dev/null
[[ "$(tr -d '[:space:]' <"${dir}/phase")" == remove ]]
[[ "$(tr -d '[:space:]' <"${dir}/attempts")" == 1 ]]
assert_grep '^reboot$' "${dir}.actions"

# second remove failure stops and does not reboot
dir="$(new_plan remove 1)"
run_phase "$dir" 1 >/dev/null
[[ "$(tr -d '[:space:]' <"${dir}/phase")" == stopped ]]
if grep -q '^reboot$' "${dir}.actions"; then
    printf 'second failure rebooted\n' >&2
    exit 1
fi
assert_grep '^mask-ly$' "${dir}.actions"

# attempts already 2: do not run the phase, do not reboot
dir="$(new_plan remove 2)"
run_phase "$dir" 0 >/dev/null
[[ "$(tr -d '[:space:]' <"${dir}/phase")" == stopped ]]
if grep -q '^prune-remove$' "${dir}.actions"; then
    printf 'third start ran prune\n' >&2
    exit 1
fi
if grep -q '^reboot$' "${dir}.actions"; then
    printf 'third start rebooted\n' >&2
    exit 1
fi

# stopped stays stopped
dir="$(new_plan stopped 2)"
printf 'remove\n' >"${dir}/stopped-phase"
run_phase "$dir" >/dev/null
[[ "$(tr -d '[:space:]' <"${dir}/phase")" == stopped ]]
[[ "$(tr -d '[:space:]' <"${dir}/attempts")" == 2 ]]
if grep -q '^reboot$' "${dir}.actions"; then
    printf 'stopped phase rebooted\n' >&2
    exit 1
fi

# install success disables, unmasks, deletes, reboots
dir="$(new_plan install 0)"
run_phase "$dir" 0 0 >/dev/null
[[ ! -d "$dir" ]]
assert_grep '^write-role$' "${dir}.actions"
assert_grep '^run-role$' "${dir}.actions"
dragon_uid="$(id -u dragon)"
dragon_home="$(getent passwd dragon | cut -d: -f6)"
[[ -n "$dragon_uid" && -n "$dragon_home" ]] || {
    printf 'could not resolve user dragon\n' >&2
    exit 1
}
assert_grep \
    "^start-user-session XDG_RUNTIME_DIR=/run/user/${dragon_uid} DOTFILES_HOME=${dragon_home}$" \
    "${dir}.actions"
assert_grep '^disable-unit$' "${dir}.actions"
assert_grep '^unmask-ly$' "${dir}.actions"
assert_grep '^delete-plan$' "${dir}.actions"
assert_grep '^reboot$' "${dir}.actions"

# early install failure is not swallowed as success
dir="$(new_plan install 0)"
run_phase "$dir" 0 0 1 >/dev/null
[[ "$(tr -d '[:space:]' <"${dir}/phase")" == install ]]
[[ "$(tr -d '[:space:]' <"${dir}/attempts")" == 1 ]]
assert_grep '^reboot$' "${dir}.actions"
if grep -q '^delete-plan$' "${dir}.actions"; then
    printf 'early install failure deleted the plan\n' >&2
    exit 1
fi

template="${repo}/setup/files/systemd/dot-files-reset.service.in"
rendered="$(sed "s|@RESET_CONTINUE@|${continue_sh}|" "$template")"
printf '%s\n' "$rendered" | grep -q 'Type=oneshot'
printf '%s\n' "$rendered" | grep -q 'Before=ly.service'
printf '%s\n' "$rendered" | grep -q 'Conflicts=ly.service'
printf '%s\n' "$rendered" | grep -q 'TimeoutStartSec=infinity'
printf '%s\n' "$rendered" | grep -q "ExecStart=${continue_sh}"
printf '%s\n' "$rendered" | grep -q 'ConditionPathExists=/var/lib/dot-files/reset-plan/phase'

printf 'reset-continue ok\n'
