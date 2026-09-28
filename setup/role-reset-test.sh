#!/usr/bin/env bash
# Guards for walk-away reset prompts. Does not remove packages or reboot.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
role="${repo}/setup/role.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

home="${work}/home"
export DOTFILES_HOME="$home"
export CONFIG_TARGET_DIR="${home}/.config"
mkdir -p "${CONFIG_TARGET_DIR}/dot-files"
printf 'workstation\n' >"${CONFIG_TARGET_DIR}/dot-files/role"
printf 'laptop\n' >"${CONFIG_TARGET_DIR}/dot-files/subroles"

real_cfg="${HOME}/.config/dot-files"
snapshot="${work}/real-snapshot"
mkdir -p "$snapshot"
if [[ -f "${real_cfg}/role" ]]; then
    cp -a "${real_cfg}/role" "${snapshot}/role"
fi
if [[ -f "${real_cfg}/subroles" ]]; then
    cp -a "${real_cfg}/subroles" "${snapshot}/subroles"
fi

default_plan="/var/lib/dot-files/reset-plan"
if [[ -e "$default_plan" ]]; then
    printf 'refusing to run; %s already exists\n' "$default_plan" >&2
    exit 1
fi

sub_count="$(grep -c '^\[subrole\.' "${repo}/setup/roles.conf")"
if [[ "$sub_count" -ne 4 ]]; then
    printf 'expected 4 known subroles so five blank answers match, found %s\n' "$sub_count" >&2
    exit 1
fi

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_real_role_unchanged() {
    local name
    for name in role subroles; do
        if [[ -f "${snapshot}/${name}" ]]; then
            cmp -s "${snapshot}/${name}" "${real_cfg}/${name}" \
                || fail "real ${name} changed"
        elif [[ -e "${real_cfg}/${name}" ]]; then
            fail "real ${name} was created"
        fi
    done
}

# --reset --force is rejected and does not remove packages.
force_out="${work}/force.out"
set +e
env -u SSH_CONNECTION -u SSH_TTY bash "$role" --reset --force >"$force_out" 2>&1
force_rc=$?
set -e
if [[ "$force_rc" -eq 0 ]]; then
    cat "$force_out" >&2
    fail "--reset --force exited 0"
fi
if ! grep -q 'walk-away' "$force_out"; then
    cat "$force_out" >&2
    fail "--reset --force output did not mention walk-away"
fi
if grep -E -q 'dnf remove|flatpak uninstall' "$force_out"; then
    cat "$force_out" >&2
    fail "--reset --force was followed by a package removal"
fi

# A role name that is only a subrole is rejected.
laptop_out="${work}/laptop.out"
set +e
bash "$role" --reset --role laptop </dev/null >"$laptop_out" 2>&1
laptop_rc=$?
set -e
if [[ "$laptop_rc" -eq 0 ]]; then
    cat "$laptop_out" >&2
    fail "--reset --role laptop exited 0"
fi
if ! grep -q 'laptop is a subrole' "$laptop_out"; then
    cat "$laptop_out" >&2
    fail "--reset --role laptop failed for the wrong reason"
fi

# No terminal and no pager skip: refuse, and do not create the default plan.
term_out="${work}/term.out"
set +e
bash "$role" --reset </dev/null >"$term_out" 2>&1
term_rc=$?
set -e
if [[ "$term_rc" -eq 0 ]]; then
    cat "$term_out" >&2
    fail "--reset without a terminal exited 0"
fi
if ! grep -q 'terminal' "$term_out"; then
    cat "$term_out" >&2
    fail "--reset without a terminal did not mention a terminal"
fi
if [[ -e "$default_plan" ]]; then
    rm -rf "$default_plan" 2>/dev/null || sudo rm -rf "$default_plan"
    fail "--reset without a terminal created ${default_plan}"
fi

# "ye" is not approval. No phase file.
ye_plan="${work}/ye-plan"
ye_out="${work}/ye.out"
set +e
printf 'ye\n' | RESET_PLAN_DIR="$ye_plan" RESET_SKIP_PAGER=1 \
    RESET_SKIP_SYSTEMCTL=1 RESET_SKIP_REBOOT=1 \
    bash "$role" --reset >"$ye_out" 2>&1
ye_rc=$?
set -e
if [[ "$ye_rc" -eq 0 ]]; then
    cat "$ye_out" >&2
    fail "ye approval exited 0"
fi
if [[ -e "${ye_plan}/phase" ]]; then
    fail "ye approval wrote ${ye_plan}/phase"
fi

# An existing plan is left alone, including a stopped phase.
stopped_plan="${work}/stopped-plan"
mkdir -p "$stopped_plan"
printf 'stopped\n' >"${stopped_plan}/phase"
stopped_out="${work}/stopped.out"
set +e
printf 'y\nyes\n' | RESET_PLAN_DIR="$stopped_plan" RESET_SKIP_PAGER=1 \
    RESET_SKIP_SYSTEMCTL=1 RESET_SKIP_REBOOT=1 \
    bash "$role" --reset >"$stopped_out" 2>&1
stopped_rc=$?
set -e
if [[ "$stopped_rc" -eq 0 ]]; then
    cat "$stopped_out" >&2
    fail "reset over an existing plan exited 0"
fi
if ! grep -q 'reset-abort' "$stopped_out"; then
    cat "$stopped_out" >&2
    fail "existing plan did not mention reset-abort"
fi
if ! grep -q '^stopped$' "${stopped_plan}/phase"; then
    fail "existing plan phase changed: $(cat "${stopped_plan}/phase")"
fi

# Abort of a missing plan is a no-op success.
missing_plan="${work}/missing-plan"
missing_out="${work}/missing.out"
set +e
RESET_PLAN_DIR="$missing_plan" bash "$role" --reset-abort >"$missing_out" 2>&1
missing_rc=$?
set -e
if [[ "$missing_rc" -ne 0 ]]; then
    cat "$missing_out" >&2
    fail "--reset-abort with no plan exited ${missing_rc}"
fi
if ! grep -q 'no reset is in progress' "$missing_out"; then
    cat "$missing_out" >&2
    fail "--reset-abort with no plan did not say no reset is in progress"
fi
if [[ -e "$missing_plan" ]]; then
    fail "--reset-abort created a missing plan"
fi

# Abort deletes the plan, prints systemctl actions, and does not reboot.
abort_plan="${work}/abort-plan"
mkdir -p "$abort_plan"
printf 'remove\n' >"${abort_plan}/phase"
printf 'marker\n' >"${abort_plan}/marker"
abort_out="${work}/abort.out"
set +e
RESET_PLAN_DIR="$abort_plan" RESET_SKIP_SYSTEMCTL=1 \
    bash "$role" --reset-abort >"$abort_out" 2>&1
abort_rc=$?
set -e
if [[ "$abort_rc" -ne 0 ]]; then
    cat "$abort_out" >&2
    fail "--reset-abort exited ${abort_rc}"
fi
if [[ -e "$abort_plan" ]]; then
    fail "--reset-abort left ${abort_plan}"
fi
if ! grep -q 'systemctl disable dot-files-reset.service' "$abort_out"; then
    cat "$abort_out" >&2
    fail "--reset-abort did not print systemctl disable"
fi
if ! grep -q 'systemctl unmask ly.service' "$abort_out"; then
    cat "$abort_out" >&2
    fail "--reset-abort did not print systemctl unmask"
fi
if grep -q 'reboot' "$abort_out"; then
    cat "$abort_out" >&2
    fail "--reset-abort rebooted or printed reboot"
fi

# YES approves the preview. Five enters keep the saved role and four
# subrole defaults. The final n declines the start, which exits 0.
decline_plan="${work}/decline-plan"
decline_out="${work}/decline.out"
set +e
printf 'YES\n\n\n\n\n\nn\n' | RESET_PLAN_DIR="$decline_plan" RESET_SKIP_PAGER=1 \
    RESET_SKIP_SYSTEMCTL=1 RESET_SKIP_REBOOT=1 \
    bash "$role" --reset >"$decline_out" 2>&1
decline_rc=$?
set -e
if [[ "$decline_rc" -ne 0 ]]; then
    cat "$decline_out" >&2
    fail "declined start exited ${decline_rc}"
fi
if [[ -e "${decline_plan}/phase" ]]; then
    fail "declined start wrote ${decline_plan}/phase"
fi
if ! grep -q '^workstation$' "${CONFIG_TARGET_DIR}/dot-files/role"; then
    fail "--reset rewrote the saved role"
fi
if ! grep -q '^laptop$' "${CONFIG_TARGET_DIR}/dot-files/subroles"; then
    fail "--reset rewrote saved subroles"
fi

assert_real_role_unchanged
printf 'role-reset guards ok\n'
