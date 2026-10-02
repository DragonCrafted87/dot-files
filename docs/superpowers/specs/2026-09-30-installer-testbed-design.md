# Installer testbed

A reusable place to run this repo's role installers. Day-to-day edits run
in an OpenMandriva container. `role.sh --reset`, and any module whose
`systemctl` call has to succeed, run in a libvirt VM cloned from a golden
install. Neither path touches a live host's home, its saved role, or its
Hyprland session.

## Locked decisions

- Container image: `openmandriva/minimal:rock` (amd64). Plain root shell.
  systemd is not PID 1.
- Container identity: user `dragon` with the invoking host uid and gid,
  passwordless sudo, hostname `testbed`, fresh home on a Docker volume.
- Repo bind-mount: host clone at `/home/dragon/dot-files` inside the
  container. The rest of the host home is not mounted.
- Secrets: opt-in. `--secrets` copies the paths in
  `setup/files/secrets.list` from the host home into the container home
  for that command and removes them when the command exits. Missing paths
  warn and are skipped.
- Hyprland source build: off for a container role run.
  `--with-hyprland-source` turns it on. An explicit
  `module install-hyprland-source` always runs that module.
- Installer scripts keep their current `systemctl` behavior. A failure
  there means that module is a VM test.
- VM base: one golden disk, produced by this testbed from
  `~/network/storage/disc-images/pc/openmandriva-6.0-plasma6-wayland.znver1.iso`.
  The Calamares install is part of `vm.sh install`. It is not a step left
  for a person at the keyboard. Hostname `testbed`, user `dragon`, sudo.
  CPU host-passthrough. Defaults: 8 GiB RAM, 80 GiB disk.
- Working disks: `/var/lib/libvirt/images/dot-files/`. Backup, required
  for a successful seal:
  `/home/dragon/network/storage/virtual-machines/dot-files/golden.qcow2`,
  plus one `golden.qcow2.bak` generation.
- The testbed is local. It is not a `roles.conf` entry and not a GitHub
  Actions job. CI stays pre-commit.
- Out of scope: graphical Hyprland in the container, the laptop reset
  investigation, extra reset logging, and a package server for Hyprland
  builds.

## Skip hook

`run_module` in `setup/lib/roles.sh` reads `DOTFILES_SKIP_MODULES`, a
comma-separated list of module basenames. A listed name logs
`skip module <name> (DOTFILES_SKIP_MODULES)` and returns 0. Any other
name runs as it does today. Unset or empty skips nothing. Surrounding
spaces and a trailing comma are ignored. A `.sh` suffix on an entry
matches the basename without it.

`role.sh` is unchanged apart from that helper. Direct
`bash path/to/module.sh` does not consult the list. The container's
`role` command exports `DOTFILES_SKIP_MODULES=install-hyprland-source`
unless `--with-hyprland-source` is set, in which case it exports an
empty list.

## Container

Script: `setup/testbed/container.sh`. Container name `dotfiles-testbed`.
Volume `dotfiles-testbed-home` mounted at `/home/dragon`. Image is pulled
when missing. Init, as root, on create: install `sudo` if it is absent,
create `dragon` with the host uid and gid, write a sudoers drop-in for
passwordless sudo. The container command is `sleep infinity`. Later
commands are `docker exec`.

| Command         | Behavior                                                                                                             |
| --------------- | -------------------------------------------------------------------------------------------------------------------- |
| `start`         | Create the container if it is missing, then start it. Idempotent.                                                    |
| `shell`         | Interactive shell as `dragon`.                                                                                       |
| `role [name]`   | `role.sh <name>` as `dragon`. Default name `workstation`. Exports the Hyprland skip unless `--with-hyprland-source`. |
| `module <name>` | That module only. The skip list is not applied.                                                                      |
| `smoke`         | Start if needed, then the checks below.                                                                              |
| `wipe-home`     | Replace the home volume. The container rootfs stays.                                                                 |
| `rebuild`       | Replace the container rootfs from the image. The home volume stays.                                                  |

`--secrets` and `--with-hyprland-source` are flags on `shell`, `role`,
`module`, and `smoke`. Changing them does not recreate the container.
Secrets are copied in for the exec and removed on the way out, including
when the exec exits non-zero. `wipe-home` is the cleanup if a kill leaves
a copy behind.

A module's non-zero status is the command's status. The container stays
up.

`smoke` runs as `dragon` and exits 0 only when all of these hold:

- uid equals the host uid
- `sudo -n true` succeeds
- `/home/dragon/dot-files/setup/role.sh` is the bind-mounted repo
- `role.sh --dry-run workstation` with the default skip prints
  `skip module install-hyprland-source`
- the same dry-run with `--with-hyprland-source` prints
  `module install-hyprland-source` and does not print that skip line

Smoke does not pass `--secrets` and does not run a live module. Dry-run
goes through the real role. Package and service helpers already honor
`DOTFILES_DRY_RUN`. A module that ignores it and fails is a smoke
failure; this design does not add skip entries to hide that.

## VM

Script: `setup/testbed/vm.sh`. Domains `dotfiles-golden` and
`dotfiles-clone`. Host SSH key
`~/.local/share/dot-files/testbed/id_ed25519`, generated on first use.
This is a testbed key, not the user's GitHub key. The Calamares password
is generated on first `install` into
`~/.local/share/dot-files/testbed/calamares-password` (mode `0600`) and
is not printed or committed. Overrides: `DOTFILES_TESTBED_ISO`,
`DOTFILES_TESTBED_BACKUP_DIR`.

| Command         | Behavior                                                                                                                                                                                                                                                                                     |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `host-check`    | Report `virsh`, `libvirtd`, and `/dev/kvm`. If the packages are missing, print `sudo dnf install qemu-kvm libvirt virt-install` and exit non-zero. It does not install them.                                                                                                                 |
| `install`       | Require those packages, enable and start `libvirtd`, and refuse if a golden disk already exists. Create the disk, boot the znver1 Plasma ISO, and complete Calamares as specified below. Return when the installed system has rebooted and SSH accepts `dragon` with the generated password. |
| `seal`          | Require SSH as `dragon`. Require `hostname -s` to be `testbed`. Install the testbed public key and a virtiofs mount of the repo at `/home/dragon/dot-files`. Shut the golden domain down. Copy the disk to the share. Exit non-zero if that copy fails.                                      |
| `backup`        | Retry the copy. Same success rule as seal.                                                                                                                                                                                                                                                   |
| `up`            | Refuse while the golden domain is running, and refuse until the share copy exists. Create a qcow2 overlay of the local golden disk if the clone disk is missing, then boot `dotfiles-clone` with the virtiofs share. A stopped clone is started as it is.                                    |
| `ssh`           | `ssh` as `dragon` with the testbed key.                                                                                                                                                                                                                                                      |
| `down`          | Shut the clone down.                                                                                                                                                                                                                                                                         |
| `destroy-clone` | Shut the clone down and delete the overlay disk only.                                                                                                                                                                                                                                        |

### Calamares

The live ISO's installer is graphical. `settings.conf` on that image
shows `welcome`, `locale`, `keyboard`, `partition`, `users`, `summary`,
then the exec phase, then `finished`. `prompt-install` is true, so the
summary page asks for a confirmation. `install` drives that session
from this machine with `virsh screenshot` and `virsh send-key` (a SPICE
viewer is fine when one is already open). It does not stop and ask
anyone else to click through.

Answers:

- Locale: English (United States), `en_US`.
- Keyboard: English (US).
- Timezone: `America/Chicago`, matching `DOTFILES_TIMEZONE`.
- Disk: erase the virtio install disk only. The ISO stays a CD. The
  result is GPT, a 300 MiB FAT32 `/boot/efi`, and the rest ext4 on `/`.
  No swap partition (`initialSwapChoice` on this ISO is `none`).
- User: full name `dragon`, login `dragon`, password from the generated
  file. Root uses the same password (`setRootPassword` is true on this
  ISO). Hostname `testbed`.
- Confirm the install prompt, wait until the finished page, then reboot
  into the installed disk.

`install` leaves `sshd` reachable with password login for `dragon`.
`seal` adds the testbed key. Password login stays available on the
golden image so the console still works.

If a page cannot be completed, `install` exits non-zero and leaves
`dotfiles-golden` running. It does not fall back to a manual step.

`role.sh --reset` stays interactive inside the guest. The driver does
not answer those prompts. A half-finished reset remains on the clone
until `destroy-clone`.

Backup write order: copy to `golden.qcow2.new` on the share, replace
`golden.qcow2.bak` with the previous `golden.qcow2`, then rename `.new`
into place. A failed copy deletes `.new`, leaves any previous backup
where it is, and returns non-zero. The local golden disk stays shut
down either way. `up` treats only the final `golden.qcow2` name as a
successful backup.

The clone's virtiofs mount is the current host checkout, so a reset
test runs the tree you have checked out. The golden image itself stays
a normal Plasma install with the distro `hyprland` package, which is
what the reset removes before `install-hyprland-source` builds into
`/usr/local`.

## Docs

- `setup/testbed/README.md` covers commands, the ISO path, disk paths,
  the backup path, the Calamares answers, and the manual VM checks.
- A short pointer in `setup/README.md`.
- The reset-role bullet in `docs/todo.md` is replaced with a pointer at
  `setup/testbed/README.md` once the scripts exist.

## Tests

Automated, on the host, no Docker: `setup/testbed/skip-modules-test.sh`.
It points `run_module` at a temporary module dir and checks that a
listed basename is skipped, an unlisted one runs, an empty
`DOTFILES_SKIP_MODULES` runs both, and a trailing comma does not skip
everything.

Container acceptance is `container.sh smoke`.

VM acceptance, recorded in the testbed README:

- `host-check` names the missing packages before they are installed
- `install` finishes at an SSH login as `dragon` on hostname `testbed`
  without a person completing Calamares
- after a successful `seal`, the share has `golden.qcow2`
- `seal` with `DOTFILES_TESTBED_BACKUP_DIR` pointed at a missing
  directory exits non-zero after the golden domain is shut down, and
  `backup` can complete the copy later
- `up` then `ssh` shows hostname `testbed` and the repo at
  `/home/dragon/dot-files`
- `destroy-clone` leaves the local golden disk and the share copy

## Files

- Create: `setup/testbed/container.sh`, `setup/testbed/vm.sh`,
  `setup/testbed/README.md`, `setup/testbed/skip-modules-test.sh`
- Modify: `setup/lib/roles.sh` (`run_module` only), `setup/README.md`,
  `docs/todo.md`

## Implementation order

1. Skip hook and `skip-modules-test.sh`.
1. `container.sh`, including `smoke`.
1. `vm.sh`, including the Calamares install and the required share
   backup.
1. README, the setup README pointer, and the todo line.

Each of those is its own change. The container and the skip hook can
land before the golden image exists. `install` is what produces that
image.
