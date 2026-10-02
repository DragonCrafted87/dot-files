# Installer testbed implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run day-to-day role installers in an OpenMandriva container, and run `role.sh --reset` in a libvirt VM whose golden disk this testbed installs with Calamares.

**Architecture:** `run_module` honors `DOTFILES_SKIP_MODULES`. `setup/testbed/container.sh` is a long-lived `openmandriva/minimal:rock` shell with a fresh home and the repo bind-mounted. `setup/testbed/vm.sh` boots the znver1 Plasma ISO, completes Calamares, seals a golden qcow2, and clones it. The golden-image backup on the storage share is required before a clone may boot.

**Tech Stack:** bash, Docker, libvirt/`virsh`/`virt-install`, OpenMandriva Rock 6.0, Calamares on the live ISO.

**Spec:** `docs/superpowers/specs/2026-09-30-installer-testbed-design.md`

## Global Constraints

- Container image is `openmandriva/minimal:rock` (amd64). systemd is not PID 1.
- Container user `dragon` uses the invoking host uid and gid, passwordless sudo, hostname `testbed`.
- Repo bind-mount is `/home/dragon/dot-files`. The rest of the host home is not mounted.
- `--secrets` copies `setup/files/secrets.list` paths for one command and removes them when the command exits.
- A container role run exports `DOTFILES_SKIP_MODULES=install-hyprland-source` unless `--with-hyprland-source` is set.
- Installer `systemctl` calls are not softened.
- Golden install ISO is `~/network/storage/disc-images/pc/openmandriva-6.0-plasma6-wayland.znver1.iso`. CPU host-passthrough. 8 GiB RAM. 80 GiB disk.
- Calamares is completed by `vm.sh install` from this machine. It is not left for someone else to click.
- Working disks live in `/var/lib/libvirt/images/dot-files/`. Backup is `/home/dragon/network/storage/virtual-machines/dot-files/golden.qcow2` plus one `.bak`.
- `up` refuses until that backup file exists, and refuses while the golden domain is running.
- A failed backup deletes `golden.qcow2.new`, leaves any previous backup, and returns non-zero.
- The testbed is not a `roles.conf` entry and not a GitHub Actions job.
- Shebang scripts keep the `.sh` extension and are executable.
- Do not commit `~/.local/share/dot-files/testbed/calamares-password` or the testbed SSH key.

## Review Focus

- A trailing comma or spaces in `DOTFILES_SKIP_MODULES` must not skip every module or fail the parser. Task 1 pins this.
- `--secrets` must remove copied files when the inner command exits non-zero. Task 2 pins this with a fake home and a failing command.
- A failed backup must not leave `golden.qcow2.new` or replace the previous `golden.qcow2`. Task 3 pins this on a temp directory.
- `up` must refuse while `dotfiles-golden` is running, even if the share copy exists. Task 3 pins the guard.
- The container user uid must match the host uid so the bind-mounted repo is not written as root. Task 2's `smoke` checks this.
- Calamares must erase only the virtio install disk. Task 4 checks `lsblk` over SSH after install and requires `/boot/efi` plus `/` on that disk.

______________________________________________________________________

### Task 1: Skip hook

**Files:**

- Modify: `setup/lib/roles.sh` (`run_module`)
- Create: `setup/testbed/skip-modules-test.sh`
- Test: `setup/testbed/skip-modules-test.sh`

**Interfaces:**

- Consumes: `log`, `die`, `find_module` from `setup/lib/lib.sh`

- Produces: `module_is_skipped` and the new `run_module` behavior. Later tasks export `DOTFILES_SKIP_MODULES`.

- [ ] **Step 1: Write the failing test**

```bash
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

export SETUP_DIR="$work"
export TEST_LOG="${work}/ran"
export REPO_ROOT="$repo"
# shellcheck disable=SC1091
. "${repo}/setup/lib/lib.sh"

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
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `bash setup/testbed/skip-modules-test.sh`

Expected: FAIL because `DOTFILES_SKIP_MODULES=alpha` still runs alpha (`alpha` then `beta` in the log).

- [ ] **Step 3: Implement the skip**

In `setup/lib/roles.sh`, add this above `run_module` and call it at the start of `run_module`:

```bash
# DOTFILES_SKIP_MODULES is a comma-separated list of basenames.
# Empty entries, surrounding spaces, and a trailing .sh are ignored.
module_is_skipped() {
    local module="${1%.sh}"
    local entry
    local list="${DOTFILES_SKIP_MODULES:-}"
    local -a entries=()

    [[ -n "$list" ]] || return 1
    module="${module##*/}"
    IFS=',' read -ra entries <<<"$list"
    for entry in "${entries[@]}"; do
        entry="${entry#"${entry%%[![:space:]]*}"}"
        entry="${entry%"${entry##*[![:space:]]}"}"
        entry="${entry%.sh}"
        [[ -n "$entry" ]] || continue
        [[ "$entry" == "$module" ]] && return 0
    done
    return 1
}

run_module() {
    local module="$1"
    local path
    if module_is_skipped "$module"; then
        log "skip module ${module} (DOTFILES_SKIP_MODULES)"
        return 0
    fi
    path="$(find_module "$module")" || die "missing module: ${module}"
    log "module ${module}"
    # shellcheck disable=SC1090
    bash "$path"
}
```

- [ ] **Step 4: Re-run the test**

Run: `bash setup/testbed/skip-modules-test.sh`

Expected: `ok`

- [ ] **Step 5: Commit**

```bash
git add setup/lib/roles.sh setup/testbed/skip-modules-test.sh
git commit -F /tmp/commit-skip.txt
```

Message: `feat: let role runs skip named modules`

______________________________________________________________________

### Task 2: Container bench

**Files:**

- Create: `setup/testbed/container.sh`
- Test: `setup/testbed/container.sh smoke` after the image pull

**Interfaces:**

- Consumes: `DOTFILES_SKIP_MODULES` from Task 1. `setup/role.sh --dry-run`.

- Produces: commands `start`, `shell`, `role`, `module`, `smoke`, `wipe-home`, `rebuild`. Flags `--secrets` and `--with-hyprland-source`.

- [ ] **Step 1: Write `container.sh`**

Executable `setup/testbed/container.sh`. Constants:

```bash
IMAGE="openmandriva/minimal:rock"
NAME="dotfiles-testbed"
VOLUME="dotfiles-testbed-home"
REPO="/home/dragon/dot-files"
```

Resolve `REPO` from the script location (`setup/testbed` → repo root), not from a hard-coded home, and bind-mount that path at `/home/dragon/dot-files` inside the container. The in-guest path stays `/home/dragon/dot-files` because `DOTFILES_USER` is `dragon`.

Behavior:

- `start` pulls the image when missing, creates the volume, and creates the container when missing with `--hostname testbed`, the repo bind-mount, and the volume at `/home/dragon`. Command: `sleep infinity`. Then `docker start`.

- On create, `docker exec -u root` runs an init that installs `sudo` if needed, `useradd`s `dragon` with `--uid` and `--gid` of the invoking user (`id -u`, `id -g`), and writes `/etc/sudoers.d/dragon` as `dragon ALL=(ALL) NOPASSWD: ALL` mode `0440`.

- `role` defaults to `workstation`. It exports `DOTFILES_SKIP_MODULES=install-hyprland-source` unless `--with-hyprland-source`, which exports `DOTFILES_SKIP_MODULES=`. It `docker exec`s as `dragon` with `REPO_ROOT=/home/dragon/dot-files` and the repo's `setup/role.sh`.

- `module <name>` execs that module file via `find` under `setup/modules` and does not export the skip list.

- `shell` is `docker exec -it -u dragon`.

- `rebuild` stops and removes the container only, then `start`. The volume stays.

- `wipe-home` stops the container, removes the volume, creates a new volume, removes the container, then `start`.

- `--secrets` reads `setup/files/secrets.list`. For each relative path that exists under `$HOME`, `docker cp` it to `/home/dragon/<path>` as root, `chown` it to `dragon`, and record the path. After the exec (success or failure), remove those paths. A missing source warns and continues. A `trap` on EXIT does the removal so a failing module still cleans up.

- [ ] **Step 2: Secrets cleanup test without a full role**

Add `setup/testbed/secrets-cleanup-test.sh` that starts the container, runs:

```bash
setup/testbed/container.sh --secrets module /bin/false
```

only if `module` can run an absolute command. Prefer a dedicated subcommand used by the test: `container.sh --secrets exec false`. If that flag pair is too much API, implement cleanup inside a function `with_secrets` and test it by `docker exec` after a forced failure:

```bash
setup/testbed/container.sh --secrets exec false
docker exec dotfiles-testbed test ! -e /home/dragon/.smbcredentials
```

Use a temp home for the source file so the test does not require the real `.smbcredentials`. The test exports `HOME` to a temp dir that contains `.smbcredentials` and a copy of the secrets list is not required if `--secrets` always reads the repo list: put a dummy `.smbcredentials` in the temp `HOME` and point the test at a one-line secrets file via `DOTFILES_TESTBED_SECRETS_LIST`.

Expected: command exits non-zero, and `docker exec dotfiles-testbed test ! -e /home/dragon/.smbcredentials` succeeds.

- [ ] **Step 3: Run smoke**

Run: `bash setup/testbed/container.sh smoke`

Expected: exit 0. Output includes `skip module install-hyprland-source` and, for the second dry-run, `module install-hyprland-source` without that skip line.

- [ ] **Step 4: Commit**

```bash
git add setup/testbed/container.sh setup/testbed/secrets-cleanup-test.sh
git commit -F /tmp/commit-container.txt
```

Message: `feat: add the OpenMandriva installer container`

______________________________________________________________________

### Task 3: VM script and backup guard

**Files:**

- Create: `setup/testbed/vm.sh`
- Create: `setup/testbed/backup-rotate-test.sh`

**Interfaces:**

- Consumes: nothing from the container.

- Produces: `host-check`, `install`, `seal`, `backup`, `up`, `ssh`, `down`, `destroy-clone`. Function `rotate_backup SRC DEST_DIR` used by `seal` and `backup`.

- [ ] **Step 1: Write the backup test first**

`rotate_backup` lives in `vm.sh`. The script must not call `main` when sourced (`return` if `BASH_SOURCE` is not `$0`... bash functions files usually end with an explicit main invocation guarded by:

```bash
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
```

Test, using a temp dir as the share:

```bash
#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
. "${repo}/setup/testbed/vm.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
echo one >"${work}/golden.qcow2"
echo two >"${work}/src.qcow2"
# Failure: dest parent missing
if rotate_backup "${work}/src.qcow2" "${work}/missing/dot-files"; then
    printf 'missing dest should fail\n' >&2
    exit 1
fi
[[ ! -e "${work}/missing/dot-files/golden.qcow2.new" ]]
[[ "$(cat "${work}/golden.qcow2")" == "one" ]]

mkdir -p "${work}/share"
rotate_backup "${work}/src.qcow2" "${work}/share"
[[ "$(cat "${work}/share/golden.qcow2")" == "two" ]]
echo three >"${work}/src.qcow2"
rotate_backup "${work}/src.qcow2" "${work}/share"
[[ "$(cat "${work}/share/golden.qcow2")" == "three" ]]
[[ "$(cat "${work}/share/golden.qcow2.bak")" == "two" ]]
printf 'ok\n'
```

`rotate_backup` copies to `DEST_DIR/golden.qcow2.new`, then if `golden.qcow2` exists moves it to `golden.qcow2.bak` (replacing an older bak), then renames `.new` to `golden.qcow2`. On copy failure it deletes `.new` and returns non-zero. A missing `DEST_DIR` is a failure before the copy.

- [ ] **Step 2: Run the test and confirm it fails**

Run: `bash setup/testbed/backup-rotate-test.sh`

Expected: FAIL, `rotate_backup` is not defined.

- [ ] **Step 3: Implement `vm.sh`**

Commands match the spec table. Details the spec does not already spell out:

- Domain names `dotfiles-golden` and `dotfiles-clone`.

- Disks `${IMAGE_DIR}/golden.qcow2` and `${IMAGE_DIR}/clone.qcow2` with `IMAGE_DIR=/var/lib/libvirt/images/dot-files`.

- ISO default `${HOME}/network/storage/disc-images/pc/openmandriva-6.0-plasma6-wayland.znver1.iso`.

- `host-check` uses `command -v virsh`, `command -v virt-install`, `systemctl is-active libvirtd`, and `[ -e /dev/kvm ]`. Missing packages print `sudo dnf install qemu-kvm libvirt virt-install` and exit 1. Confirm those package names with `dnf list` on this host before freezing the string; if the provider names differ, print the names that actually provide `virsh` and `virt-install`.

- `install` enables and starts `libvirtd` only after the packages exist. It refuses when the golden disk exists.

- `virt-install` uses `--cpu host-passthrough`, `--memory 8192`, `--disk size=80` (qcow2 at the golden path), `--cdrom` the ISO, `--os-variant` detect or `linux2022`, `--graphics spice`, UEFI firmware (`--boot uefi`), and a virtio disk so the installer disk is `/dev/vda`.

- `domain_running NAME` is `virsh domstate`. `up` calls it for `dotfiles-golden` and exits 1 if the state is `running`. `up` also requires the backup file `${BACKUP_DIR}/golden.qcow2` to exist. Default `BACKUP_DIR` is `/home/dragon/network/storage/virtual-machines/dot-files`.

- `up` creates the overlay with `qemu-img create -f qcow2 -b <golden> -F qcow2 <clone>` when the clone disk is missing. The clone domain gets a virtiofs share of the repo tagged `dotfiles`, mounted in the guest at `/home/dragon/dot-files` by the unit `seal` installed.

- `destroy-clone` runs `down` and deletes only the clone disk and the clone domain.

- SSH key path `~/.local/share/dot-files/testbed/id_ed25519`. Generate with `ssh-keygen -t ed25519 -N '' -f` that path when missing.

- Password path `~/.local/share/dot-files/testbed/calamares-password`, created mode `0600` with `openssl rand -base64 24` when missing. Never `echo` it.

- `seal` SSHes as `dragon`, checks `hostname -s`, installs the pubkey into `~/.ssh/authorized_keys`, writes a systemd mount unit for virtiofs tag `dotfiles`, shuts the domain down with `virsh shutdown` and waits until `shut off`, then `rotate_backup`.

- [ ] **Step 4: Re-run the backup test**

Run: `bash setup/testbed/backup-rotate-test.sh`

Expected: `ok`

- [ ] **Step 5: Guard test for `up`**

Add to `backup-rotate-test.sh` or a sibling a case that stubs `domain_running` by extracting the guard:

```bash
up_allowed() {
    local golden_state="$1"
    local backup_file="$2"
    [[ "$golden_state" != "running" ]] || return 1
    [[ -f "$backup_file" ]] || return 1
}
```

Assert `up_allowed running /any` fails, `up_allowed "shut off" /missing` fails, and `up_allowed "shut off"` of a real temp file succeeds.

- [ ] **Step 6: Commit**

```bash
git add setup/testbed/vm.sh setup/testbed/backup-rotate-test.sh
git commit -F /tmp/commit-vm.txt
```

Message: `feat: add the libvirt installer VM`

Do not commit a golden disk, a password, or an SSH private key.

______________________________________________________________________

### Task 4: Complete the Calamares install

**Files:**

- Modify: `setup/testbed/vm.sh` (`install` drives the guest)
- Modify: `setup/testbed/README.md` (answers and checks; Task 5 owns the rest of the README if this task only adds the Calamares section)

**Interfaces:**

- Consumes: `install` from Task 3, which already boots the ISO.

- Produces: a shut-down-or-running golden domain whose installed system matches the checklist below. `seal` can then log in with the generated password.

- [ ] **Step 1: Boot and drive Calamares**

Run `bash setup/testbed/vm.sh install` on this host.

Drive the guest with `virsh screenshot dotfiles-golden <file>` and `virsh send-key dotfiles-golden <key>`. Page order on this ISO:

1. welcome
1. locale — English (United States), `en_US`
1. keyboard — English (US)
1. partition — Erase disk, the virtio disk only (`/dev/vda`), swap none, ext4
1. users — full name `dragon`, login `dragon`, hostname `testbed`, password from `~/.local/share/dot-files/testbed/calamares-password`, root password the same value
1. summary — confirm the install prompt
1. finished — reboot onto the disk

Timezone `America/Chicago` when the locale page asks.

The ISO is a CD. Do not erase it. There is one virtio disk.

- [ ] **Step 2: Verify the installed system**

After reboot, SSH with the password file (sshpass or `SSH_ASKPASS`) as `dragon`:

```bash
hostname -s    # testbed
findmnt / /boot/efi
lsblk -o NAME,TRAN,MOUNTPOINT
```

Expected: `/` is ext4 on the virtio disk, `/boot/efi` is vfat about 300 MiB, and no second disk was formatted. `sshd` accepts this login.

If a page cannot be completed, `install` exits non-zero and leaves the domain running. Do not add a "finish by hand" path.

- [ ] **Step 3: Seal and check the share**

Run: `bash setup/testbed/vm.sh seal`

Expected: exit 0, domain shut off, and
`/home/dragon/network/storage/virtual-machines/dot-files/golden.qcow2` exists.

Then point `DOTFILES_TESTBED_BACKUP_DIR` at a missing directory and run `seal` again only if the domain can be started without undoing the install. The cheap check is `backup` against a missing directory:

```bash
DOTFILES_TESTBED_BACKUP_DIR=/tmp/does-not-exist-dotfiles-backup \
    bash setup/testbed/vm.sh backup
```

Expected: non-zero, no `golden.qcow2.new` left under that path, and the real share copy unchanged.

- [ ] **Step 4: Commit**

Only script and docs changes. The qcow2 stays on the host and on the share.

```bash
git add setup/testbed/vm.sh
git commit -F /tmp/commit-calamares.txt
```

Message: `feat: drive Calamares for the golden installer image`

______________________________________________________________________

### Task 5: Docs

**Files:**

- Create: `setup/testbed/README.md`
- Modify: `setup/README.md`
- Modify: `docs/todo.md` (only the reset-role bullet that asks for a test container or VM)

**Interfaces:**

- Consumes: the command names from Tasks 2 and 3.

- [ ] **Step 1: Write `setup/testbed/README.md`**

Include the command tables, the ISO path, the disk directory, the backup path, the Calamares answers, and the VM checks from the spec's Tests section. State that `role.sh --reset` stays interactive inside the clone.

- [ ] **Step 2: Point setup/README.md at it**

After the "Reset without reinstalling" section, add a short paragraph:

```markdown
Installer changes can be tried in the OpenMandriva container, and a
role reset in the libvirt clone, before they run on a live machine.
See [testbed/README.md](testbed/README.md).
```

- [ ] **Step 3: Update the todo bullet**

In `docs/todo.md`, replace the reset-role line about a test docker container or VM with a pointer to `setup/testbed/README.md`. Leave the logging bullet and the laptop-reset bullet as they are.

- [ ] **Step 4: Commit**

```bash
git add setup/testbed/README.md setup/README.md docs/todo.md
git commit -F /tmp/commit-docs.txt
```

Message: `docs: describe the installer testbed`

Leave unrelated dirty files unstaged. `docs/todo.md` may already have other edits; stage only the reset-role bullet if the rest of the file is someone else's work. If the whole file is already dirty with unrelated edits, put the pointer in `setup/README.md` and skip `docs/todo.md` rather than mixing those edits into this commit.

______________________________________________________________________

## Self-review

Spec coverage:

- Skip hook, container commands, secrets, smoke, VM commands, Calamares answers, backup rotation, `up` guards, docs, and tests each have a task.
- GitHub Actions stays untouched.
- `systemctl` inside modules is not changed.

Placeholder scan: package names for libvirt are verified against `dnf` in Task 3 rather than guessed if the printed line is wrong. Calamares key names are not a fixed macro; Task 4 drives from screenshots because the live session's focus order is not stable enough to hard-code a key script.

Type consistency: `rotate_backup SRC DEST_DIR`, domain names `dotfiles-golden` / `dotfiles-clone`, container name `dotfiles-testbed`, and `DOTFILES_SKIP_MODULES` match across tasks.
