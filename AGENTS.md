# Agent notes for this repo

Personal dot-files for OpenMandriva Rock (Hyprland) and Windows.
Clone lives at `~/dot-files`. The user is `dragon`. Do not invent a
second clone path.

Read this before exploring the tree. Host-specific Hyprland behavior is
in `config/hypr/README.md` and `config/hypr/REQUIREMENTS.md`. Role
install is in `setup/README.md`. Planned-but-not-done layout notes are
in `docs/structure.md`.

## Workflow

- `main` is protected. Work on a feature branch and open a PR.
- Re-running `setup/role.sh <role>` is the upgrade path. Do not add a
  second installer.
- `link-user-config.sh` links every **directory** under `config/` to
  `~/.config/<dirname>`. Drop a folder there; do not edit the linker for
  a new app config.
- Loose files in `config/` are ignored by the linker.
- `config/Code` is not linked as a whole tree (VS Code rewrites settings).
- Saved Linux role: `~/.config/dot-files/role`.
- Recorded clone path: `~/.config/dot-files/root` (`DOTFILES_ROOT`).
- Hostname checks use `hostname -s` (`runewyrm`, `forgewyrm`, ...).

## Layout

| Path           | Role                                                                             |
| -------------- | -------------------------------------------------------------------------------- |
| `shell/`       | Linux / Git Bash / root bashrc entrypoints, Oh My Posh theme                     |
| `bashrc.d/`    | Sourced snippets. Must stay at repo root (`DOTFILES_ROOT` is parent of this dir) |
| `config/`      | Linked into `~/.config`                                                          |
| `setup/`       | Role installer: `role.sh`, `roles.conf`, `modules/`, `files/`                    |
| `scripts/`     | User helpers (ffmpeg, dictation). Not installed by roles                         |
| `setup/files/` | Files roles install (udev, BOINC prefs, CUPS, pre-commit wrapper)                |
| `windows/`     | Winget lists and PowerShell                                                      |
| `docs/`        | Notes, not executed                                                              |

Do not merge `scripts/` and `setup/files/`.

## Shebang files

Anything with a `#!` line must have an extension that matches the
interpreter (`.sh`, `.py`, `.ps1`, …) **unless** it is installed onto
`PATH` as a command name (`/usr/local/bin/boincmgr`,
`~/.local/bin/brave-browser`). Those installed binaries may stay
extensionless. Repo copies that are *not* the installed name (wrappers,
modules, helpers, `exec-once` scripts) keep the extension. Do not add a
bare `setup/files/foo` with a shebang and then `install` it as `foo.sh`.

## Setup modules

- Lists in `setup/roles.conf`. `[common]` always runs. `laptop` is a
  subrole of `workstation` (`[subrole.laptop]`).
- Roles: `workstation`, `htpc`, `server`.
- Modules source `${REPO_ROOT:-$DOTFILES_ROOT}/setup/lib/lib.sh`.
- `setup/lib/lib.sh` is the only import. It loads the pieces under `setup/lib/`.
- `roles.conf` stores the basename. `run_module` looks the file up.
- Prefer adding a module + a `roles.conf` line over growing an unrelated
  script. Color/theme work for an app belongs in that app's install
  module (office → `install-office-printing`, games →
  `install-gaming-packages`, KDE chrome → `configure-mime-defaults`).
- `configure-litra-glow` installs hidraw udev for Logitech Litra Glow
  (`046d:c900`) and adds the user to `video`.
- `configure-piper-g603` installs `piper` / `ratbagd`, udev rules for
  G603/G604 Lightspeed HID++, a hidraw rescan oneshot so ratbagd sees
  the mice after hid-logitech-hidpp binds, and a user oneshot that
  forces ratbag profile 0 after Windows G HUB overwrites onboard storage.
- `configure-astro-wallpaper` installs `hyprpaper` and a daily user
  timer. `scripts/astro-wallpaper.py` pulls astronomy stills and sets one
  image per enabled monitor.
- Modules run in a subprocess (`bash module.sh`), so env vars do not
  survive back to `role.sh`. Cross-module flags and other short-lived
  files go in `/tmp` (example:
  `/tmp/dot-files-<uid>-need-qs-restart`). Do not write throwaway state
  under `~/.config/dot-files/`.
- `request_qs_restart` sets that flag. `role.sh` calls
  `restart_qs_if_needed` at the end of an `update-role` / role run.

## Hyprland (`config/hypr`)

Shared tree across machines. Host layouts are files, not hard-coded in
scripts.

- Monitors: `conf.d/monitors.d/<host>.conf` or `<host>-<profile>.conf`.
- Ports / HDMI-switch / idle output: `conf.d/hosts.d/<host>.conf`.
- Audio per profile: `conf.d/audio.d/<host>-<profile>.conf`.
- `display-profile.sh` applies `monitor=` lines via `hyprctl keyword`.
- `display-switch.sh` owns the saved profile and calls `display-audio.sh`.
- Last profile: `~/.local/state/hypr/display-profile` (not in git).
- `exec-once` restore runs once at login. `hyprctl reload` does not
  re-apply the profile.

### runewyrm (desk workstation)

- Profiles: `desk` (triple head + S/PDIF soundbar),
  `theater` (HDMI ELMO + GPU HDMI 7.1),
  `workshare` (HDMI AOC + soundbar).
- `SUPER+SHIFT+D` desk. `SUPER+SHIFT+S` single (theater vs workshare from
  HDMI EDID) and starts `display-switch.sh watch`.
- Default audio sink on desk/workshare is the onboard S/PDIF soundbar
  `alsa_output.pci-0000_18_00.6.iec958-stereo`, **not** the Jabra.
- Keyboard `XF86Audio*` binds use `@DEFAULT_AUDIO_SINK@` (soundbar).

### Workspaces

`SUPER+0-9` runs `python3 ~/.config/hypr/scripts/switch-workspace.py N`.
Visible workspace: focus that monitor. Hidden: `moveworkspacetomonitor`
to the monitor under the cursor, then focus it.

The filename is hyphenated. Keep `# pylint: disable=invalid-name` at the
top. Call it with `python3`; do not rely on a shebang plus executable
bit (pre-commit `check-executables-have-shebangs`).

### Logitech G603 / G604

Windows G HUB on the work computer overwrites onboard profiles. A udev
rule starts `reset-piper-profile.service`, which sets Piper profile 0
through `ratbagctl`. hid-logitech-hidpp bind also starts
`ratbagd-hidraw-rescan.service` so ratbagd retries Lightspeed child
nodes that were missing at daemon start. Role module:
`configure-piper-g603`.

### Astronomy wallpapers

`astro-wallpaper.sh apply` at login. Daily timer at 06:30 runs `refresh`.
`display-switch.sh` re-applies after a layout change. One still per
enabled monitor via hyprpaper. `SUPER+SHIFT+W` forces a new set.

### Litra Glow + Insta360 Link

`scripts/litra-camera-lights.py watch` is `exec-once`. It turns every
USB Litra Glow on while the Insta360 Link (`2e1a:*`) has an open V4L2
node, with a 1.5s debounce so browser probes do not flash the lamps.

### Jabra Speak 710

Present on runewyrm USB hub `0000:18:00.3-2.1` (full-speed,
`0b0e:2475`). Analog profile + `PCM` mixer 0-11. Call audio (Discord
WebRTC) plays to this sink; desk media stays on the soundbar.

Volume/mute helpers are bash functions in `bashrc.d/jabra.bashrc`:

```bash
jabra-volume 50
jabra-volume 100
jabra-mute
jabra-unmute
```

Those target the Jabra PipeWire sink/source only. Do not wire Jabra
buttons to the default sink.

Known limitation: while Discord has the Insta360 Link (`5-2.2` on the
same Realtek hub) streaming, the 710 hardware pads often stop affecting
volume on Linux. Same dock works on Windows. There is no evdev/hidraw
report for those pads. Do not re-add a Jabra HID watcher unless new
evidence appears. Insta360 also exposes an ALSA card; do not make that
the default audio source.

## Shell

`shell/linux.bashrc` sources `~/.bashrc.d/*.bashrc` (symlink to repo
`bashrc.d/`). New interactive helpers go there as functions, not as
`/usr/local/bin` wrappers, unless a role must install a root-owned
binary (BOINC, xbox-controller).

`update-dot-files` pulls the repo and re-sources bashrc.
`update-role` re-runs the saved role.

## pre-commit

Docker wrapper from `install-python-dev`. Hooks live in
`config/git/template`. CI: `.github/workflows/pre-commit.yml`.

Expectations that bite:

- Python: black, isort (single-line imports), flake8 120, pylint with
  `.pylintrc`. Prefer f-strings (C0209).
- Hyphenated module names fail C0103; disable at file top if the name
  must stay hyphenated.
- Bash: beautysh indent 4, shellcheck error severity.
- Markdown: mdformat + markdownlint.
- Shebang files must be executable, and executable files must have a
  shebang. Hyprland `exec` of `python3 file.py` avoids that pair.
- Exclude `.scratch/`.

```bash
pre-commit run
pre-commit run --all-files
```

## Hardware map (runewyrm)

| Device                  | Where                                               |
| ----------------------- | --------------------------------------------------- |
| Desk soundbar           | onboard S/PDIF, default sink                        |
| Jabra Speak 710         | USB FS `5-2.1`, calls                               |
| Insta360 Link           | USB HS `5-2.2`, V4L2 `/dev/video0`, MJPG            |
| Litra Glow pair         | USB `5-2.3` and `5-2.4`, `046d:c900`                |
| Logitech G604 (pair)    | Lightspeed `046d:c539` / device `046d:4085`         |
| Valve Index / 3D camera | other controller (`16:00.0`), ignore for desk calls |

PipeWire is 1.4.x + WirePlumber. Volume CLI is `wpctl`.

## Do not

- Point desk default sink at the Jabra.
- Grab Jabra evdev (`EVIOCGRAB`) so keyboard volume keys stay on the
  soundbar.
- Treat `docs/structure.md` as current layout; several items there are
  already done.
- Commit secrets. Transfer with `setup/utility/transfer-secrets.sh`.
- Overwrite an existing real `~/.config/<name>` directory; the linker
  will skip it.
