# Role reset walk-away

Date: 2026-09-27
Status: approved design

## Purpose

Replace `setup/role.sh --reset` so a person can review the package
removal, confirm the role, and leave. The machine then reboots, strips
extra packages, reboots, runs a normal role update, and reboots a last
time. A workstation or HTPC comes back at the Ly greeter. A server
comes back at the text console, because that role does not install Ly.

The run is expected to take on the order of an hour, mostly the
Hyprland source build inside the role update. Nobody needs to be
present after the last prompt.

## Success criteria

- `--reset` from a graphical session, a text console, or SSH shows the
  removal preview in `less`, requires an explicit yes, then asks the
  role and subrole questions, then asks once more to start.
- Saying no, or quitting `less`, schedules nothing and does not reboot.
- After the start answer, there are no further prompts.
- The remove boot builds a fresh removal list with the same rules as
  the preview. It does not delete a saved snapshot.
- The install boot runs the normal role update for the role and
  subroles chosen in the prompts.
- Each of those two phases may fail once, reboot, and try again. A
  second failure of that phase does not reboot. A later power cycle
  does not try a third time.
- `--reset --force` no longer removes packages in the current session.

## Out of scope

- `git pull` before the role update. This is a role run, not
  `update-dot-files`.
- Auto-login. The last boot stops at Ly or a getty.
- Editing the ISO baseline, `iso-strip.list`, or `never-remove.list`
  except if a test shows the prune script still cannot find them.
- A main menu that can be revisited. The prompts are a fixed sequence.
- Running a real reset, or rebooting this machine, as part of
  implementation.

## Current behavior

`role.sh --reset` prints extras and exits. `role.sh --reset --force`
removes them immediately, and only from a real VT or SSH, then tells
the operator to run the role by hand. It does not reinstall the role.

`prune-extra-packages.py` lives at
`setup/modules/common/prune-extra-packages.py` and sets `SETUP_DIR` to
`parent.parent`, which is `setup/modules/`. The package lists are in
`setup/files/packages/`. The preview cannot find them until that path
is corrected to `setup/`.

Removal rules stay as they are:

- Keep names in the ISO list unless they match `iso-strip.list`.
- Keep `never-remove.list`.
- Keep the hard-coded prefixes and names already in the Python file
  (`kernel`, `grub2`, `systemd`, `glibc`, `dnf`, `rpm-`, `basesystem`,
  plus `filesystem`, `setup`, `bash`, `sudo`, `rpm`).
- Remove every other installed rpm.
- Remove every installed Flatpak app.
- Changing the role does not change this set. The role only chooses
  what the install boot puts back.

## Interactive flow

Entry points:

```bash
~/dot-files/setup/role.sh --reset
update-role --reset
```

`update-role` already forwards extra arguments, so it needs no new
function.

Flags:

| Flag                               | Effect                                                                                             |
| ---------------------------------- | -------------------------------------------------------------------------------------------------- |
| `--role workstation\|htpc\|server` | Pre-selects that role in the picker                                                                |
| `--enable-subrole NAME`            | Pre-selects that known subrole as enabled. Repeatable                                              |
| `--disable-subrole NAME`           | Pre-selects that known subrole as disabled. Repeatable                                             |
| `--dry-run`                        | Prints the preview and the reboot plan, then exits. No pager, no prompts, no phase file, no reboot |
| `--reset-abort`                    | Cancels a scheduled, running, or stopped reset. No reboot                                          |
| `--force`                          | Error. Tell the operator that `--reset` is the walk-away flow                                      |

`--role laptop` is an error. Laptop is a subrole
(`--enable-subrole laptop`). Unknown subrole names are an error before
the pager.

`--reset` and `--reset-abort` together are an error.

`--reset` requires a terminal. `--dry-run` and `--reset-abort` do not.

If a phase directory already exists, `--reset` refuses and tells the
operator to let it finish or run `--reset-abort`.

Prompt order:

1. Run the prune program in list-only mode (no `dnf`, no `flatpak uninstall`) and open that output in `less`. Print one line above
   the pager: the remove boot computes this list again, and the role
   does not change it. `less` is on the ISO baseline.
1. `Approve this removal preview? [y/N]`. Accept only `y` or `yes`,
   case insensitive. Anything else, including Enter, exits without
   writing state.
1. Role picker. The default is the saved role, or `--role` when that
   flag was passed. Offer only `workstation`, `htpc`, and `server`.
   Enter accepts the default.
1. One prompt per known subrole from `roles.conf`. The default is the
   saved state, with `--enable-subrole` and `--disable-subrole` applied
   on top. Choices are enabled or disabled. Enter accepts the default.
1. Print the plan: fresh removal on the next boot, then the chosen
   role and subroles, then a final boot to Ly (or the console for
   `server`). `Start now? [y/N]`, same yes rule as the approval.
   This is the last prompt.

On start:

1. Write the phase directory as root.
1. Install and enable `dot-files-reset.service`.
1. If enable fails, delete the phase directory and do not reboot.
1. `systemctl reboot`.

The chosen role and subroles are stored in the phase directory. Do not
change `~/.config/dot-files/role` or `subroles` until the install phase
begins, so a failed remove leaves the previous role files in place.

## Phase directory

Path: `/var/lib/dot-files/reset-plan/`
Owner: root. Mode: `0755` on the directory, `0644` on the files.

| File       | Contents                                                   |
| ---------- | ---------------------------------------------------------- |
| `phase`    | `remove`, `install`, or `stopped`                          |
| `attempts` | Integer. Starts at `0` for a phase                         |
| `user`     | The account that ran `--reset`                             |
| `repo`     | Absolute dot-files clone path                              |
| `role`     | `workstation`, `htpc`, or `server`                         |
| `subroles` | Enabled subrole names, one per line. Empty file if none    |
| `log`      | Not stored here. The log is `/var/log/dot-files-reset.log` |

No rpm list and no Flatpak list are stored.

## Boot job

One system oneshot, installed when the reset is scheduled, not by a
role module. The unit file in the repo is a template. The scheduler
writes `/etc/systemd/system/dot-files-reset.service` with the absolute
path to `setup/files/systemd/reset-continue.sh`.

The service:

- `Type=oneshot`
- Runs as root
- `After=network-online.target` and `Wants=network-online.target`
- `Before=ly.service` and `Conflicts=ly.service`
- `ConditionPathExists` on the `phase` file
- `TimeoutStartSec=infinity`, so a source build is not killed at the
  default service timeout
- `WantedBy=multi-user.target`
- stdout and stderr go to the journal and the console

`network-online.target` keeps its own timeout. This job does not wait
forever for the network. If the network is down, the phase fails and
the retry rule below applies.

The continue script exports `RESET_FROM_BOOT=1` when it runs the prune
program. That is the only bypass of the VT-or-SSH check. The
interactive preview never sets it, and it never removes packages.

## Phases

### `remove`

Increment `attempts` and write it before doing work. If the value is
now greater than 2, go to the stopped behavior without removing
anything.

Run the prune program with removal enabled and `RESET_FROM_BOOT=1`.
It recomputes the rpm and Flatpak sets and removes them. An empty set
is success.

On success: set `phase=install`, set `attempts=0`, then reboot.
On failure: follow the retry rule. Leave `phase=remove`.

### `install`

Same attempt increment and the same greater-than-2 guard.

As `user`, write `~/.config/dot-files/role` and
`~/.config/dot-files/subroles` from the phase files, then run:

```bash
bash "$repo/setup/role.sh" "$role"
```

with `HOME` set from that account's passwd entry and `USER` set to
`user`. Do not hard-code `/home/dragon`. Do not pass `--reset`.
Saved subroles are how `role.sh` decides which subrole modules run, so
the file write is required before the role script.

On success:

1. `systemctl disable dot-files-reset.service`
1. `systemctl unmask ly.service` (no error if Ly is not installed)
1. Delete the phase directory
1. Reboot

The role enables `ly.service` for workstation and HTPC. Enable does
not unmask, so the unmask above is required when an earlier failure
masked Ly. The last boot does not start this job, and Ly is free to
start. The server role does not install Ly; that boot stops at the
getty.

On failure: follow the retry rule. Leave `phase=install`. Do not
disable the job and do not delete the phase directory.

### `stopped`

Mask `ly.service`, print the phase that stopped, the attempt count, the
log path, and the `--reset-abort` command on the console, then exit
without rebooting. Do not increment `attempts`. A later boot hits this
same branch.

## Retry rule

The counter is per phase. A successful remove sets `attempts` back to 0
before the install boot, so the install phase has its own two tries.

On failure, after `attempts` was incremented at the start of the try:

- `attempts` is 1: reboot. The next boot runs the same phase.
- `attempts` is 2 or more: set `phase=stopped`, mask Ly, and do not
  reboot.

A power loss after the increment and before success consumes that try.
That is deliberate, so a crash cannot reboot without limit.

## Abort

`role.sh --reset-abort`:

- Disables `dot-files-reset.service`
- Unmasks `ly.service`
- Deletes the phase directory
- Does not reboot
- If no phase directory exists, print that no reset is in progress and
  exit 0

Abort does not roll back packages already removed and does not restore
the old role files if the install phase already wrote them.

## Files

| Path                                             | Change                                                                                                                                    |
| ------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `setup/role.sh`                                  | Replace the reset flags, prompts, schedule, and abort                                                                                     |
| `setup/modules/common/prune-extra-packages.py`   | Point `SETUP_DIR` at `setup/`. List-only stays the default. Removal still requires the existing confirm switch. Honor `RESET_FROM_BOOT=1` |
| `setup/files/systemd/reset-continue.sh`          | New root phase script                                                                                                                     |
| `setup/files/systemd/dot-files-reset.service.in` | Unit template                                                                                                                             |
| `tests/reset-continue-test.sh`                   | State-machine test. Not a role module and not installed                                                                                   |
| `setup/README.md`                                | Replace "Reset without reinstalling"                                                                                                      |

`bashrc.d/setup.bashrc` stays unchanged. `update-role --reset` already
works because `update-role` forwards its extra arguments.

Do not add a `roles.conf` line. The boot job is installed by `--reset`,
because it has to exist before the role runs.

## Testing

Implementation must not schedule a real reset and must not reboot the
machine.

- List-only prune, after the path fix, finds
  `setup/files/packages/iso-installed.txt` and exits without running
  `dnf` or `flatpak uninstall`. Running that preview on the workstation
  is allowed.
- `tests/reset-continue-test.sh` uses a temporary phase directory and
  `RESET_CONTINUE_DRY_RUN=1`. That switch records reboot, disable,
  unmask, and prune/role actions instead of performing them. It asserts:
  - success moves `remove` to `install` with `attempts=0` and requests
    one reboot
  - the first failure of a phase requests one reboot and leaves the
    phase in place
  - the second failure sets `stopped` and does not request a reboot
  - a later run with `phase=stopped` does not request a reboot
  - install success requests disable, unmask, deletion, and one reboot
- `pre-commit run` on the staged shell and Python files.

## Decisions

- One systemd job and one phase directory, not a chain of units and not
  a cron script.
- Guided prompts, not a main menu. Flags only change the picker
  defaults.
- The pager approves the rules, not a frozen package list.
- Two tries per phase, then a hard stop, including across power loss.
- Failure does not fall through to Ly. Stop masks Ly until abort.
- Workstation and HTPC end at Ly. Server ends at the console.
