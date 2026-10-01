# Installer testbed

Two benches for the role installer. The container is the everyday bench:
add a package, move a file, re-run a role or one module. The VM is for
`role.sh --reset` and for modules whose `systemctl` calls must succeed.
Neither one is a `roles.conf` module.

The repo is bind-mounted in the container and shared into the clone with
virtiofs, both at `/home/dragon/dot-files`. Live `~/.config`, SSH keys, and
`gh` stay on the host.

## Container

Script: `setup/testbed/container.sh`. Image `openmandriva/minimal:rock`.
Name `dotfiles-testbed`. Home volume `dotfiles-testbed-home`. The guest
user `dragon` uses the invoking uid and gid, with passwordless sudo, and
the hostname is `testbed`.

```bash
bash setup/testbed/container.sh start
bash setup/testbed/container.sh role
bash setup/testbed/container.sh role htpc
bash setup/testbed/container.sh module install-hyprland-session
bash setup/testbed/container.sh shell
bash setup/testbed/container.sh smoke
bash setup/testbed/container.sh wipe-home
bash setup/testbed/container.sh rebuild
```

| Command         | Behavior                                                     |
| --------------- | ------------------------------------------------------------ |
| `start`         | Create the container if it is missing, then start it.        |
| `shell`         | Interactive shell as `dragon`.                               |
| `role [name]`   | `role.sh <name>`. Default `workstation`.                     |
| `module <name>` | That module only.                                            |
| `smoke`         | Start if needed, then the dry-run checks below.              |
| `wipe-home`     | Replace the home volume. The container root stays.           |
| `rebuild`       | Replace the container from the image. The home volume stays. |

`role` exports `DOTFILES_SKIP_MODULES=install-hyprland-source` unless
`--with-hyprland-source` is set. `module` does not apply the skip list, so
`module install-hyprland-source` builds Hyprland. `--secrets` copies the
paths in `setup/files/secrets.list` in for that command and removes them
when it exits, including on failure. A missing secret warns and continues.

`smoke` exits 0 only when the guest uid matches the host, `sudo -n true`
works, the repo bind is `/home/dragon/dot-files`, a dry-run prints
`skip module install-hyprland-source`, and the same dry-run with
`--with-hyprland-source` prints `module install-hyprland-source` without
that skip line.

## VM

Script: `setup/testbed/vm.sh`. Domains `dotfiles-golden` and
`dotfiles-clone`.

| Path     | What                                                                           |
| -------- | ------------------------------------------------------------------------------ |
| ISO      | `~/network/storage/disc-images/pc/openmandriva-6.0-plasma6-wayland.znver1.iso` |
| Disks    | `/var/lib/libvirt/images/dot-files/` (`golden.qcow2`, `clone.qcow2`)           |
| Backup   | `/home/dragon/network/storage/virtual-machines/dot-files/golden.qcow2`         |
| SSH key  | `~/.local/share/dot-files/testbed/id_ed25519`                                  |
| Password | `~/.local/share/dot-files/testbed/calamares-password` (mode `0600`)            |

Overrides: `DOTFILES_TESTBED_ISO`, `DOTFILES_TESTBED_IMAGE_DIR`,
`DOTFILES_TESTBED_BACKUP_DIR`. The key and the password are generated on
first use, never printed, and never committed. The key is not the GitHub
key.

`host-check` prints this install line when a package is missing, and does
not install it:

```bash
sudo dnf install qemu-kvm qemu-img libvirt-utils virt-install virtiofsd ovmf lib64osinfo-gir1.0 osinfo-db
```

| Command         | Behavior                                                                                                          |
| --------------- | ----------------------------------------------------------------------------------------------------------------- |
| `host-check`    | Report `virsh`, `libvirtd`, and `/dev/kvm`.                                                                       |
| `install`       | Boot the ISO and complete Calamares. Refuses if the golden disk exists.                                           |
| `seal`          | Require hostname `testbed`, install the testbed key and the virtiofs unit, shut down, copy the disk to the share. |
| `backup`        | Copy again. Refuses while the golden domain is running.                                                           |
| `up`            | Boot the throwaway clone. Refuses while golden is running or the share copy is missing.                           |
| `ssh`           | Shell on the clone as `dragon`.                                                                                   |
| `down`          | Shut the clone down.                                                                                              |
| `destroy-clone` | Delete the overlay only.                                                                                          |

```bash
bash setup/testbed/vm.sh host-check
bash setup/testbed/vm.sh install
bash setup/testbed/vm.sh seal
bash setup/testbed/vm.sh up
bash setup/testbed/vm.sh ssh
bash setup/testbed/vm.sh destroy-clone
```

The console is VNC on `127.0.0.1`. `install` drives Calamares with
`virsh screenshot` and `virsh send-key`. If a page cannot be completed it
exits non-zero and leaves `dotfiles-golden` running.

Calamares answers:

- Locale English (United States), `en_US`. Keyboard English (US).
- Timezone `America/Chicago`.
- Erase the virtio disk only. GPT, 300 MiB FAT32 `/boot/efi`, the rest
  ext4 on `/`, no swap partition.
- Full name and login `dragon`, hostname `testbed`, password from the
  generated file. Root uses the same password.

After reboot, `/` is ext4 on the virtio disk, `/boot/efi` is vfat of about
300 MiB, and the ISO was not formatted. `sshd` accepts `dragon` with that
password. `seal` adds the testbed public key. Password login stays so the
console still works.

The backup copy goes to `golden.qcow2.new`, the previous file becomes
`golden.qcow2.bak`, then `.new` is renamed into place. A missing backup
directory fails before anything is written. A failed copy deletes `.new`
and leaves the previous backup. `up` also refuses until
`golden.qcow2` exists on the share.

`role.sh --reset` stays interactive inside the clone. The driver does not
answer those prompts. When a reset test is done, `destroy-clone` drops the
overlay. The golden image keeps the distro Hyprland package, which is what
a reset removes before the source build.

Checks worth re-running after a new golden image:

- `host-check` names missing packages before they are installed
- `install` reaches an SSH login as `dragon` on hostname `testbed`
- `seal` leaves `golden.qcow2` on the share
- `backup` with `DOTFILES_TESTBED_BACKUP_DIR` pointed at a missing
  directory exits non-zero and does not leave `golden.qcow2.new`
- `up` then `ssh` shows hostname `testbed` and the repo at
  `/home/dragon/dot-files`
- `destroy-clone` leaves the local golden disk and the share copy
