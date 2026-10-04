---
name: setup-roles
description: Use when changing a role, a setup module, roles.conf, or a source-build pin.
---

# Setup roles

## Roles

Module lists live in `setup/roles.conf`. `[common]` always runs.
`laptop` is a subrole of `workstation` (`[subrole.laptop]`). The roles
are `workstation`, `htpc`, and `server`. The HTPC couch session plan is
`docs/htpc-role.md`, and that work is paused. Role install detail is in
`setup/README.md`.

Re-running `setup/role.sh <role>` upgrades a machine. `update-role`
re-runs the saved role.

## Modules

A module sources `${REPO_ROOT:-$DOTFILES_ROOT}/setup/lib/lib.sh`. That
file is the only import, and it loads the pieces under `setup/lib/`.
`roles.conf` stores the basename. `run_module` looks the file up.

A new behavior is a module plus a `roles.conf` line. Color and theme
work for an app goes in that app's install module. Office goes in
`install-office-printing`, games go in `install-gaming-packages`, and
KDE chrome goes in `configure-mime-defaults`.

Source-build pins live in `setup/versions.conf`. `lib.sh` loads a pin
unless the same key is already in the environment.

Each module runs as `bash module.sh`. Environment variables do not
survive back to `role.sh`. A cross-module flag is a file under `/tmp`,
for example `/tmp/dot-files-<uid>-need-qs-restart`. `request_qs_restart`
sets that flag. `role.sh` calls `restart_qs_if_needed` at the end of an
`update-role` or role run.

## Installed behavior

`install-hyprland-session` enables `ly.service` and the user session
units. It does not install the OpenMandriva Hyprland packages.

`install-hyprland-source` builds the pinned Hyprland tag and the
hyprland ecosystem into `/usr/local` when `rpm -q hyprland` fails.
While that package is installed, the module exits without building.
The Ly session entry for Hyprland is
`Exec=/usr/local/bin/start-hyprland`. The source prefix is `/usr/local`.

`configure-litra-glow` installs hidraw udev for the Logitech Litra Glow
(`046d:c900`) and adds the user to `video`.

`configure-ratbag` installs `ratbagd` and the Piper GUI, udev rules for
the G603 and G604 Lightspeed HID++, a hidraw rescan oneshot so ratbagd
sees the mice after hid-logitech-hidpp binds, and a user oneshot that
forces ratbag profile 0 after Windows G HUB overwrites onboard storage.

`configure-astro-wallpaper` installs `hyprpaper` and a daily user
timer. `scripts/astro-wallpaper.py` pulls astronomy stills and sets one
image per enabled monitor.

`configure-xdg-user-dirs` pins lowercase XDG directories (`~/desktop`,
`~/downloads`, and the rest) and sets `enabled=False` so login does not
recreate the English CamelCase names. `~/network` is the CIFS, NFS, and
rclone parent from `install-network-mounts`.

`configure-locale` installs `setup/files/locale/locale.conf` to
`/etc/locale.conf`, with byte-order `LC_COLLATE=C` and ISO
`LC_TIME=en_DK`, plus the matching KDE Formats file. `en_DK` needs the
`locales-en` package.
