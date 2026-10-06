# Agent notes for this repo

Personal dot-files have one clone. The host records that root, and the
linker and the role read it, so a second clone path is a fiction.

`main` is protected, so a change lands on a feature branch.

`setup/role.sh` is a temporary helper. It checks out machine-setup
for this machine's role and execs that checkout's `setup/role.sh`.
The modules live in machine-setup. A second installer would fork a
machine off the role.

The linker publishes directories and skips a real `~/.config/<name>`
that is already there. A loose file is not a config, and replacing a
directory the linker skipped would destroy a config it refused to own.
`config/Code` stays unlinked because VS Code rewrites that tree.
`bashrc.d/` stays at the repo root because the shell records that
parent while it is sourcing the file. `scripts/` stays here. Role
modules and `setup/files/` live in machine-setup.

A shebang in the repo keeps an interpreter extension because the hook
pairs a shebang with the executable bit. The installed command name is
the exception.

A module runs in a subprocess, so a flag for a later module is a file
under `/tmp`, and throwaway state does not go under
`~/.config/dot-files/`.

Source Hyprland builds into `/usr/local`, and only when the distro
package is absent. `/usr` belongs to that package.

Host layouts are files so the Hyprland scripts stay shared across
machines. The display profile is restored once at login, so a reload
is not a layout change.

Desk media and the keyboard volume keys stay on the onboard soundbar.
Pointing the default sink at the Jabra, or grabbing its evdev node,
would move those keys. The Jabra pads have no evdev or hidraw report,
so a HID watcher stays out until new evidence appears. The Insta360
ALSA card is not the default source.

The astronomy timer tears down processes it started, so it restarts
the hyprpaper unit instead of spawning hyprpaper.

`docs/todo.md` is future work, so it is not the state of the machine.
Secrets stay out of commits.

`docs/plans` and `docs/specs` point at the parent repository when this
checkout is a submodule. Those files stay out of this repository's
history.

This repository uses Kobold Codex. Skills for this repo are in
`.agents/skills/`.
