<!-- cspell:disable -->

# Role Reset Walk-Away Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `setup/role.sh --reset` with a reviewed, then unattended, remove-reboot-install-reboot flow that stops after two failed tries of a phase.

**Architecture:** `role.sh --reset` previews removals, asks the role questions, and writes `/var/lib/dot-files/reset-plan/`. A root oneshot, `dot-files-reset.service`, runs `setup/reset-continue.sh` before Ly on the next boots. That script recomputes the removal list, then runs a normal `role.sh` for the chosen role. Dry-run environment variables make the state machine testable without rebooting.

**Tech Stack:** bash, python3, systemd system units, dnf, flatpak, less.

**Spec:** `docs/superpowers/specs/2026-09-27-role-reset-design.md`

## Global Constraints

- Do not schedule a real reset and do not reboot this machine during implementation.
- `--reset --force` must not remove packages. `--force` is an error.
- The remove boot recomputes the list. Do not save an rpm or Flatpak snapshot.
- Two tries per phase. Attempt 1 failure reboots. Attempt 2 failure sets `phase=stopped`, masks Ly, and does not reboot. A later boot of `stopped` does not reboot.
- Increment `attempts` and write it before doing the phase work. A value greater than 2 stops without doing the work.
- A successful remove sets `phase=install` and `attempts=0` before it reboots.
- Do not change `~/.config/dot-files/role` or `subroles` until the install phase starts.
- Install success disables the unit, unmasks `ly.service`, deletes the phase directory, then reboots.
- Workstation and HTPC end at Ly. Server ends at the text console. Do not install Ly for server.
- Do not `git pull`. Do not auto-login.
- `bashrc.d/setup.bashrc` stays unchanged. Do not add a `roles.conf` line.
- Removal rules stay in `prune-extra-packages.py`. The only prune behavior changes are the `setup/` path, list-only as the default, and `RESET_FROM_BOOT=1`.
- Home directory comes from the passwd entry for the user recorded in the phase file. Do not hard-code `/home/dragon`.
- Accept only `y` or `yes`, case insensitive, for both confirms. Enter means no.
- `--reset` requires a terminal. `--dry-run` and `--reset-abort` do not.
- `--role laptop` is an error. Laptop is `--enable-subrole laptop`.

## Review Focus

- A boot that finds `attempts` already at 2 must not remove packages and must not reboot. Expected: set `stopped`, mask Ly, exit.
- Enter, `ye`, or `yep` at either confirm must not write a phase directory and must not reboot. Expected: exit without state changes. `YES` and `y` approve.
- `role.sh --reset --force` must not call `dnf` or `flatpak uninstall`. Expected: non-zero exit and the walk-away error.
- A second `--reset` while a phase directory exists must not overwrite it and must not reboot. Expected: non-zero exit naming `--reset-abort`.
- `--reset` with stdin closed must exit before `less` and before creating a phase directory. Expected: non-zero exit about needing a terminal.

______________________________________________________________________

### Task 1: Fix the prune package-list path

**Files:**

- Modify: `setup/modules/common/prune-extra-packages.py`
- Create: `setup/prune-list-test.sh`
- Test: `setup/prune-list-test.sh`

**Interfaces:**

- Consumes: `setup/files/packages/iso-installed.txt`, `iso-strip.list`, `never-remove.list`

- Produces: `SETUP_DIR` resolves to the `setup/` directory. List-only when `RESET_CONFIRM` is not `yes`. `RESET_FROM_BOOT=1` skips the VT check and still does not remove unless `RESET_CONFIRM=yes`.

- [ ] **Step 1: Write the failing test**

Create `setup/prune-list-test.sh`:

```bash
#!/usr/bin/env bash
# Prove list-only prune finds the ISO list and does not remove packages.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
py="${repo}/setup/modules/common/prune-extra-packages.py"
log="$(mktemp)"
bindir="$(mktemp -d)"
trap 'rm -rf "$bindir" "$log"' EXIT

cat >"${bindir}/dnf" <<'EOF'
#!/bin/sh
printf 'dnf %s\n' "$*" >>"${DNF_LOG:?}"
exit 99
EOF
cat >"${bindir}/flatpak" <<'EOF'
#!/bin/sh
printf 'flatpak %s\n' "$*" >>"${DNF_LOG:?}"
exit 0
EOF
cat >"${bindir}/rpm" <<'EOF'
#!/bin/sh
printf 'bash\nextra-demo-pkg\n'
EOF
chmod 755 "${bindir}/dnf" "${bindir}/flatpak" "${bindir}/rpm"

DNF_LOG="$log" PATH="${bindir}:${PATH}" python3 "$py" >"${log}.out" 2>"${log}.err" || true
grep -q 'iso-installed.txt' "${log}.out"
grep -q 'extra-demo-pkg' "${log}.out"
if grep -q '^dnf ' "$log"; then
    printf 'dnf was invoked during list-only\n' >&2
    exit 1
fi
if grep -q 'flatpak uninstall' "$log"; then
    printf 'flatpak uninstall was invoked during list-only\n' >&2
    exit 1
fi
printf 'prune list-only ok\n'
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `bash setup/prune-list-test.sh`

Expected: FAIL because the script dies looking for `setup/modules/files/packages/iso-installed.txt`.

- [ ] **Step 3: Point SETUP_DIR at setup/ and bypass the VT check only for the boot job**

In `setup/modules/common/prune-extra-packages.py`, replace the `SETUP_DIR` assignment:

```python
SETUP_DIR = Path(__file__).resolve().parent.parent.parent
```

At the start of `require_reset_session`:

```python
if os.environ.get("RESET_FROM_BOOT") == "1":
    log("reset session: boot job")
    return
```

Leave the `RESET_CONFIRM=yes` requirement in place. Do not remove packages when that variable is unset, including when `RESET_FROM_BOOT=1`.

- [ ] **Step 4: Re-run the test**

Run: `bash setup/prune-list-test.sh`

Expected: `prune list-only ok`

- [ ] **Step 5: Commit**

```bash
git add setup/modules/common/prune-extra-packages.py setup/prune-list-test.sh
git commit -m "$(cat <<'EOF'
Fix the role-reset package list path.

The prune script walked up one directory too few after the module move,
so the ISO list was invisible. List-only still refuses to call dnf.
EOF
)"
```

### Task 2: Boot-phase state machine

**Files:**

- Create: `setup/reset-continue.sh`
- Create: `setup/reset-continue-test.sh`
- Test: `setup/reset-continue-test.sh`

**Interfaces:**

- Consumes: phase directory files `phase`, `attempts`, `user`, `repo`, `role`, `subroles`. Environment `RESET_PLAN_DIR` (default `/var/lib/dot-files/reset-plan`), `RESET_CONTINUE_DRY_RUN=1`, `RESET_TEST_REMOVE_RC`, `RESET_TEST_INSTALL_RC`, `RESET_ACTION_LOG`.

- Produces: action-log lines `prune-remove`, `write-role`, `run-role`, `reboot`, `mask-ly`, `disable-unit`, `unmask-ly`, `delete-plan`. On dry-run these are written to `RESET_ACTION_LOG` and nothing is rebooted.

- [ ] **Step 1: Write the failing test**

Create `setup/reset-continue-test.sh` with this body:

```bash
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
    local dir="$1" remove_rc="${2:-0}" install_rc="${3:-0}"
    local actions="${dir}.actions"
    : >"$actions"
    set +e
    RESET_PLAN_DIR="$dir" \
        RESET_CONTINUE_DRY_RUN=1 \
        RESET_ACTION_LOG="$actions" \
        RESET_TEST_REMOVE_RC="$remove_rc" \
        RESET_TEST_INSTALL_RC="$install_rc" \
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
assert_grep '^disable-unit$' "${dir}.actions"
assert_grep '^unmask-ly$' "${dir}.actions"
assert_grep '^delete-plan$' "${dir}.actions"
assert_grep '^reboot$' "${dir}.actions"

printf 'reset-continue ok\n'
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `bash setup/reset-continue-test.sh`

Expected: FAIL because `setup/reset-continue.sh` does not exist.

- [ ] **Step 3: Implement the continue script**

Create `setup/reset-continue.sh`, `chmod 755` it, and use this body:

```bash
#!/usr/bin/env bash
# Continue a scheduled role reset across boots. Installed as a system unit.
set -euo pipefail

PLAN_DIR="${RESET_PLAN_DIR:-/var/lib/dot-files/reset-plan}"
LOG_FILE="${RESET_LOG:-/var/log/dot-files-reset.log}"
DRY="${RESET_CONTINUE_DRY_RUN:-0}"
ACTION_LOG="${RESET_ACTION_LOG:-}"

log_line() {
    printf '==> %s\n' "$*"
    if [[ "$DRY" != 1 ]]; then
        printf '%s %s\n' "$(date -Is)" "$*" >>"$LOG_FILE" || true
    fi
}

record() {
    printf '%s\n' "$1"
    if [[ -n "$ACTION_LOG" ]]; then
        printf '%s\n' "$1" >>"$ACTION_LOG"
    fi
}

read_trim() {
    tr -d '[:space:]' <"$1"
}

write_trim() {
    printf '%s\n' "$2" >"$1"
}

do_reboot() {
    record reboot
    if [[ "$DRY" == 1 ]]; then
        return 0
    fi
    systemctl reboot
}

do_mask_ly() {
    record mask-ly
    if [[ "$DRY" == 1 ]]; then
        return 0
    fi
    systemctl mask ly.service || true
}

do_disable_unit() {
    record disable-unit
    if [[ "$DRY" == 1 ]]; then
        return 0
    fi
    systemctl disable dot-files-reset.service
}

do_unmask_ly() {
    record unmask-ly
    if [[ "$DRY" == 1 ]]; then
        return 0
    fi
    systemctl unmask ly.service || true
}

stop_forever() {
    local which="$1" attempts="$2"
    write_trim "${PLAN_DIR}/phase" stopped
    write_trim "${PLAN_DIR}/stopped-phase" "$which"
    do_mask_ly
    log_line "dot-files reset stopped after ${attempts} failed attempts of phase ${which}"
    log_line "log: ${LOG_FILE}"
    log_line "clear with: role.sh --reset-abort"
}

run_remove() {
    record prune-remove
    if [[ "$DRY" == 1 ]]; then
        return "${RESET_TEST_REMOVE_RC:-0}"
    fi
    local repo
    repo="$(read_trim "${PLAN_DIR}/repo")"
    RESET_CONFIRM=yes RESET_FROM_BOOT=1 \
        python3 "${repo}/setup/modules/common/prune-extra-packages.py"
}

run_install() {
    record write-role
    record run-role
    if [[ "$DRY" == 1 ]]; then
        return "${RESET_TEST_INSTALL_RC:-0}"
    fi
    local repo role user home
    repo="$(read_trim "${PLAN_DIR}/repo")"
    role="$(read_trim "${PLAN_DIR}/role")"
    user="$(read_trim "${PLAN_DIR}/user")"
    home="$(getent passwd "$user" | cut -d: -f6)"
    [[ -n "$home" && -d "$home" ]] || return 1
    install -d -o "$user" -g "$user" "${home}/.config/dot-files"
    install -m 0644 -o "$user" -g "$user" "${PLAN_DIR}/role" "${home}/.config/dot-files/role"
    install -m 0644 -o "$user" -g "$user" "${PLAN_DIR}/subroles" "${home}/.config/dot-files/subroles"
    sudo -u "$user" -H env HOME="$home" USER="$user" \
        bash "${repo}/setup/role.sh" "$role"
}

finish_install() {
    do_disable_unit
    do_unmask_ly
    record delete-plan
    rm -rf "$PLAN_DIR"
    do_reboot
}

run_attempt() {
    local phase attempts rc=0
    phase="$(read_trim "${PLAN_DIR}/phase")"
    if [[ "$phase" == stopped ]]; then
        do_mask_ly
        log_line "dot-files reset is stopped"
        log_line "log: ${LOG_FILE}"
        log_line "clear with: role.sh --reset-abort"
        return 0
    fi
    attempts="$(read_trim "${PLAN_DIR}/attempts")"
    attempts=$((attempts + 1))
    write_trim "${PLAN_DIR}/attempts" "$attempts"
    if [[ "$attempts" -gt 2 ]]; then
        stop_forever "$phase" "$attempts"
        return 0
    fi
    case "$phase" in
        remove) run_remove || rc=$? ;;
        install) run_install || rc=$? ;;
        *)
            stop_forever "$phase" "$attempts"
            return 0
            ;;
    esac
    if [[ "$rc" -eq 0 ]]; then
        if [[ "$phase" == remove ]]; then
            write_trim "${PLAN_DIR}/phase" install
            write_trim "${PLAN_DIR}/attempts" 0
            do_reboot
        else
            finish_install
        fi
        return 0
    fi
    if [[ "$attempts" -ge 2 ]]; then
        stop_forever "$phase" "$attempts"
    else
        do_reboot
    fi
}

[[ -f "${PLAN_DIR}/phase" ]] || exit 0
run_attempt
```

`RESET_CONTINUE_DRY_RUN=1` must not call `systemctl`, `dnf`, or `sudo`. Disable, unmask, and delete happen before reboot so a crash cannot leave the unit enabled.

- [ ] **Step 4: Re-run the test**

Run: `bash setup/reset-continue-test.sh`

Expected: `reset-continue ok`

- [ ] **Step 5: Commit**

```bash
git add setup/reset-continue.sh setup/reset-continue-test.sh
git commit -m "$(cat <<'EOF'
Add the role-reset boot phase script.

One root script walks remove, then install, and stops for good after
the second failure of a phase instead of rebooting again.
EOF
)"
```

### Task 3: Systemd unit template

**Files:**

- Create: `setup/files/systemd/dot-files-reset.service.in`
- Modify: `setup/reset-continue-test.sh`
- Test: `setup/reset-continue-test.sh`

**Interfaces:**

- Consumes: nothing at runtime until Task 4 renders it

- Produces: template token `@RESET_CONTINUE@` replaced with the absolute path of `setup/reset-continue.sh`

- [ ] **Step 1: Extend the test**

Append this before the final `printf` in `setup/reset-continue-test.sh`:

```bash
template="${repo}/setup/files/systemd/dot-files-reset.service.in"
rendered="$(sed "s|@RESET_CONTINUE@|${continue_sh}|" "$template")"
printf '%s\n' "$rendered" | grep -q 'Type=oneshot'
printf '%s\n' "$rendered" | grep -q 'Before=ly.service'
printf '%s\n' "$rendered" | grep -q 'Conflicts=ly.service'
printf '%s\n' "$rendered" | grep -q 'TimeoutStartSec=infinity'
printf '%s\n' "$rendered" | grep -q "ExecStart=${continue_sh}"
printf '%s\n' "$rendered" | grep -q 'ConditionPathExists=/var/lib/dot-files/reset-plan/phase'
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `bash setup/reset-continue-test.sh`

Expected: FAIL because the template does not exist.

- [ ] **Step 3: Add the template**

Create `setup/files/systemd/dot-files-reset.service.in`:

```ini
[Unit]
Description=Continue dot-files role reset
After=network-online.target
Wants=network-online.target
Before=ly.service
Conflicts=ly.service
ConditionPathExists=/var/lib/dot-files/reset-plan/phase

[Service]
Type=oneshot
ExecStart=@RESET_CONTINUE@
TimeoutStartSec=infinity
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 4: Re-run the test**

Run: `bash setup/reset-continue-test.sh`

Expected: `reset-continue ok`

- [ ] **Step 5: Commit**

```bash
git add setup/files/systemd/dot-files-reset.service.in setup/reset-continue-test.sh
git commit -m "$(cat <<'EOF'
Add the role-reset systemd unit template.

The boot job runs before Ly and is not killed by the default service
timeout while the role rebuilds Hyprland.
EOF
)"
```

### Task 4: Interactive reset, abort, and schedule

**Files:**

- Modify: `setup/role.sh`
- Create: `setup/role-reset-test.sh`
- Test: `setup/role-reset-test.sh`

**Interfaces:**

- Consumes: `known_subroles`, `read_saved_subroles`, `read_saved_role`, `valid_subrole`. Prune list-only from Task 1. Template from Task 3.

- Produces: `role.sh --reset`, `--reset-abort`, and the rejection of `--force`. Honors `RESET_PLAN_DIR`, `RESET_SKIP_PAGER=1`, `RESET_SKIP_SYSTEMCTL=1`, `RESET_SKIP_REBOOT=1`. Default plan directory is `/var/lib/dot-files/reset-plan`.

- [ ] **Step 1: Write the failing tests**

Create `setup/role-reset-test.sh`. It exports `DOTFILES_HOME` and `CONFIG_TARGET_DIR` to a temp home containing `dot-files/role` = `workstation` and `subroles` = `laptop`. Then:

- `bash role.sh --reset --force` exits non-zero and the combined output contains `walk-away`. It must not be followed by a package removal.

- `bash role.sh --reset --role laptop </dev/null` exits non-zero.

- `bash role.sh --reset </dev/null` exits non-zero, mentions a terminal, and does not create `/var/lib/dot-files/reset-plan`.

- `printf 'ye\n' | RESET_PLAN_DIR=$tmp RESET_SKIP_PAGER=1 RESET_SKIP_SYSTEMCTL=1 RESET_SKIP_REBOOT=1 bash role.sh --reset` exits non-zero and does not write `$tmp/phase`.

- With `$tmp/phase` already `stopped`, a piped `y` / `yes` reset exits non-zero, leaves `phase` as `stopped`, and mentions `reset-abort`.

- `role.sh --reset-abort` with a missing `RESET_PLAN_DIR` prints `no reset is in progress` and exits 0.

- `role.sh --reset-abort` with `RESET_SKIP_SYSTEMCTL=1` deletes an existing temp plan and does not reboot.

- `printf 'YES\n\n\n\n\n\nn\n' | RESET_PLAN_DIR=$tmp RESET_SKIP_PAGER=1 RESET_SKIP_SYSTEMCTL=1 RESET_SKIP_REBOOT=1 bash role.sh --reset` exits 0 and does not write `$tmp/phase`. The blank lines accept the default role and the four current subroles. The final `n` declines the start. `YES` must be accepted as the preview approval or this case fails for the wrong reason.

- [ ] **Step 2: Run the test and confirm it fails**

Run: `bash setup/role-reset-test.sh`

Expected: FAIL because `--force` is still accepted.

- [ ] **Step 3: Replace the reset path in role.sh**

Keep parsing `--reset` and `--force`. Add `--reset-abort`.

Before any removal and before `RESET_CONFIRM=yes`:

- Both `--reset` and `--reset-abort`: usage error.
- `--force`: `die "--force does not strip packages; role.sh --reset is the walk-away flow"`.
- `--reset-abort`: disable `dot-files-reset.service`, unmask `ly.service`, delete the plan directory, do not reboot. If the directory is absent, print `no reset is in progress` and exit 0. `RESET_SKIP_SYSTEMCTL=1` prints the systemctl action instead of running it.
- `--role laptop`: `die "laptop is a subrole; use --enable-subrole laptop"`.
- Plan directory already present: `die "a reset is already scheduled; role.sh --reset-abort clears it"`.
- `--dry-run --reset`: print the list-only preview and the reboot plan, then exit. No pager and no prompts.
- `--reset` when stdin is not a terminal, unless `RESET_SKIP_PAGER=1`: `die "role.sh --reset needs a terminal"`.

Preview with `RESET_CONFIRM` unset, using the Python file next to `prune-extra-packages.sh`. Print `The remove boot computes this list again. The role does not change it.` then show the preview in `less`, or print it when `RESET_SKIP_PAGER=1`.

`confirm_yes` reads one line and accepts only `y` or `yes` after lowercasing. Enter returns failure. First prompt: `Approve this removal preview?`. Failure exits 1 with no plan.

Role choices are `workstation`, `htpc`, `server`. Default is the saved role, or `--role` when passed. Enter keeps the default. For each `known_subroles` name, default enabled if saved or passed to `--enable-subrole`, and disabled if passed to `--disable-subrole`. Enter keeps that default.

Last prompt: `Start now?`. No exits 1 without a plan file.

Yes writes `phase=remove`, `attempts=0`, `user`, `repo`, `role`, and `subroles` into the plan directory, renders the unit template over `@RESET_CONTINUE@`, installs it to `/etc/systemd/system/dot-files-reset.service`, daemon-reloads, and enables it. `RESET_SKIP_SYSTEMCTL=1` skips install and enable. Then reboot, unless `RESET_SKIP_REBOOT=1`, which prints `reboot`. If enable fails, delete the plan directory and do not reboot.

Do not modify `~/.config/dot-files/role` in `--reset`. Remove the old block that runs a forced prune and exits. A plain `role.sh workstation` stays as it is.

- [ ] **Step 4: Re-run the tests**

Run: `bash setup/prune-list-test.sh && bash setup/reset-continue-test.sh && bash setup/role-reset-test.sh`

Expected: each script prints its ok line. The machine does not reboot.

- [ ] **Step 5: Commit**

```bash
git add setup/role.sh setup/role-reset-test.sh
git commit -m "$(cat <<'EOF'
Replace role reset with the walk-away prompts.

--reset previews removals, asks for the role, and schedules the boot
job. --force no longer deletes packages in the current session.
EOF
)"
```

### Task 5: Document the new reset

**Files:**

- Modify: `setup/README.md` (section "Reset without reinstalling")
- Test: `bash setup/role-reset-test.sh`

**Interfaces:**

- Consumes: the flags from Task 4

- Produces: README text that matches those flags

- [ ] **Step 1: Replace the section**

Replace "Reset without reinstalling" so it states:

- `--reset` shows the removal preview, asks for approval, then asks about the role and subroles.

- The last yes reboots. Later boots remove packages, run the normal role update, and reboot once more.

- Workstation and HTPC stop at Ly. Server stops at the text console.

- Examples: `--reset`, `--reset --role htpc`, `--dry-run --reset`, `--reset-abort`.

- `--force` is not a reset flag.

- Quitting the pager or answering no schedules nothing.

- A failed phase reboots once and retries. A second failure stays on the console until `--reset-abort`.

- [ ] **Step 2: Re-run the guard test**

Run: `bash setup/role-reset-test.sh`

Expected: `role-reset guards ok`

- [ ] **Step 3: Commit**

```bash
git add setup/README.md
git commit -m "$(cat <<'EOF'
Document the walk-away role reset.

The README now matches the reboot sequence and drops the immediate
--force strip.
EOF
)"
```

- [ ] **Step 4: Run the staged hooks**

Run: `pre-commit run --files setup/role.sh setup/reset-continue.sh setup/prune-list-test.sh setup/reset-continue-test.sh setup/role-reset-test.sh setup/modules/common/prune-extra-packages.py setup/README.md setup/files/systemd/dot-files-reset.service.in docs/superpowers/specs/2026-09-27-role-reset-design.md docs/superpowers/plans/2026-09-27-role-reset.md`

Expected: the hooks pass. Do not reboot the machine.
