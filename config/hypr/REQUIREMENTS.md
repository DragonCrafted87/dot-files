# Display and audio script requirements

Normative rules for `config/hypr` display/audio behavior. Host layouts and
keybinds stay in `README.md`.

Keywords follow RFC 2119: MUST, MUST NOT, SHOULD, MAY.

## Scope

These scripts implement workstation monitor and sink switching:

| Script                                               | Owns                                                                           |
| ---------------------------------------------------- | ------------------------------------------------------------------------------ |
| `scripts/display-switch.sh`                          | Saved profile name, HDMI-switch watch lifecycle, calling the other two scripts |
| `scripts/display-profile.sh`                         | `hyprctl keyword monitor`, idle DPMS, workspace map restore                    |
| `scripts/display-audio.sh`                           | PipeWire/Pulse default sink and card profile                                   |
| `scripts/idle-display-off.sh` / `idle-display-on.sh` | Lock/sleep wrappers around `display-profile.sh` idle commands                  |

`conf.d/monitors.conf` MUST contain only startup `exec-once`. It MUST NOT
contain a `monitor =` rule. Host layouts MUST live in `conf.d/monitors.d/`.
Audio policy MUST live in `conf.d/audio.d/`. Port and switch metadata
MUST live in `conf.d/hosts.d/<hostname>.conf`.

## Process and language

1. Scripts MUST be `#!/usr/bin/env bash` with `set -euo pipefail`.
1. Scripts MUST be executable and safe to run with no arguments.
1. Scripts MUST NOT source each other. Orchestration is process calls
   from `display-switch.sh` (or idle wrappers) only.
1. Hostname-specific constants MUST NOT be hardcoded in scripts when a
   `hosts.d`, `monitors.d`, or `audio.d` key can hold them.
1. Conf files that Hyprland does not parse (`hosts.d`, `audio.d`, and
   `MATCH_DESC=` lines) MUST be `KEY=value` lines with `#` comments.
1. Scripts MUST treat missing optional tools (`pactl`, `inotifywait`,
   `notify`) as skippable: print a message, do not abort the profile
   apply.
1. User-facing commands MUST print a one-line `Usage:` on unknown flags
   (`-h` / `--help` / `help`).

## State

State MUST live under `${XDG_STATE_HOME:-$HOME/.local/state}/hypr`,
never in the git-linked `~/.config/hypr` tree.

| File                       | Writer                        | Readers                                   |
| -------------------------- | ----------------------------- | ----------------------------------------- |
| `display-profile`          | `display-switch.sh` only      | switch, profile (idle), audio, steam wrap |
| `display-switch.pid`       | `display-switch.sh` watch     | switch start/stop/status                  |
| `saved-monitor-workspaces` | `display-profile.sh` idle-off | profile idle-on                           |
| `apply.lock`               | `display-profile.sh`          | profile only                              |

1. `display-profile.sh` MUST NOT write `display-profile`.
1. `display-audio.sh` MUST NOT write `display-profile`.
1. The saved profile value MUST be a single trimmed token (`desk`,
   `theater`, `workshare`, or another `monitors.d/<host>-<name>.conf`
   suffix).
1. If the state file is missing, restore MUST use `desk` when that
   profile exists, otherwise the host default layout.

## Responsibility split

### display-switch.sh

MUST:

- Read and write the saved profile name.
- On `desk`, `single`, `restore`, or a named profile: apply monitors
  via `display-profile.sh <profile>`, then audio via
  `display-audio.sh <profile>`, then update state.
- On `single`: detect the panel on `SWITCH_PORT` and pick a name from
  `SINGLE_PROFILES` using `MATCH_DESC`.
- Start the watch daemon only after a single-output profile is active.
- Stop the watch daemon before applying `desk` (or any profile not in
  `SINGLE_PROFILES`).
- On compositor start (`restore`): reapply the saved profile and start
  watch only if that profile is in `SINGLE_PROFILES`.

MUST NOT:

- Issue `hyprctl keyword monitor`.
- Call `pactl` directly.
- Leave a watch process running after desk is applied.
- Poll DRM in a sleep loop when `inotifywait` is available.

MAY accept `theater` / `workshare` as explicit profile names. Those
MUST still start or stop watch according to `SINGLE_PROFILES`.

### display-profile.sh

MUST:

- Apply only `monitor=` lines from `monitors.d`.
- Implement `idle-off` / `idle-on` / `restore-ws` for hypridle.
- Read the saved profile name to choose which conf idle reapplies.
- Serialize apply/idle with `apply.lock`.

MUST NOT:

- Change the default audio sink or card profile.
- Start or stop the HDMI-switch watcher.
- Write the saved profile name.
- Put host `monitor=` rules into `conf.d/monitors.conf`.

### display-audio.sh

MUST:

- Load `audio.d/<host>-<profile>.conf` (and stereo fallback when
  configured).
- Set the default sink with `pactl` and move existing sink inputs.

MUST NOT:

- Change monitors.
- Write the saved profile name.
- Start or stop the HDMI-switch watcher.

## HDMI switch

Applies only when `hosts.d/<host>.conf` defines `SWITCH_PORT` and
`SINGLE_PROFILES`.

1. Theater and workshare MUST share the same physical connector
   (`SWITCH_PORT`). The attached panel MUST select the profile.
1. Detection MUST use `hyprctl monitors` identity (description / make /
   model / serial) against each single profile's `MATCH_DESC`
   (case-insensitive substring).
1. If no `MATCH_DESC` hits, `DEFAULT_SINGLE_PROFILE` MUST be used when
   set; otherwise `single` MUST fail with a message.
1. Watch MUST daemonize with `setsid` and record the session leader PID
   in `display-switch.pid`.
1. Watch MUST block on `inotifywait` for
   `/sys/class/drm/<SWITCH_DRM>/{status,edid}` (or `card*-<SWITCH_PORT>`
   if `SWITCH_DRM` is unset).
1. After an inotify event, watch MUST wait until the port has a live
   mode, then compare a status+EDID fingerprint, then apply only if the
   detected single profile changed.
1. Disconnect / missing EDID MUST NOT flip the saved profile to desk.
1. Watch MUST exit when the saved profile is no longer in
   `SINGLE_PROFILES`, or when `stop` / `desk` kills the process group.
1. `inotify-tools` missing: `single` MUST still apply the current panel
   and MUST print that watch cannot start. It MUST NOT fall back to a
   permanent sleep poll.

## Startup and reload

1. `monitors.conf` MUST `exec-once` only
   `display-switch.sh restore`.
1. `monitors.conf` MUST NOT contain any `monitor =` rule. A wildcard
   `monitor = , highrr, auto, 1` is re-parsed on `hyprctl reload` and
   re-autoplaces outputs, which shuffles order and positions.
1. Hyprland reload MUST NOT re-run restore or apply. `keyword monitor`
   during reload can disable DP outputs and loop the compositor.
1. `display-profile.sh apply` as `exec-once` MUST NOT exist.
1. A delayed second `exec-once` for audio MUST NOT exist; `restore`
   already applies audio. (HDMI ELD may still lag; `display-audio.sh`
   SHOULD be idempotent so the user can rerun it.)

## Keybinds

1. Desk MUST be its own bind (`SUPER+SHIFT+D` → `display-switch.sh desk`).
1. Single-output MUST be one bind (`SUPER+SHIFT+S` →
   `display-switch.sh single`), not separate theater and workshare binds.
1. Binds MUST call `display-switch.sh`, not `display-profile.sh` or
   `display-audio.sh` directly.

## Idle and lock

1. hypridle / lock MUST call `idle-display-off.sh` /
   `idle-display-on.sh`, not `display-switch.sh`.
1. Idle MUST NOT change the saved profile or the audio sink.
1. On runewyrm, idle-off MUST save the workspace map, DPMS the desk
   ports if they are part of the active layout, then disable
   `IDLE_MONITOR` so HDMI cannot wake itself.
1. Idle-on MUST reapply the active monitor conf and restore workspaces.

## Audio

1. Desk on runewyrm MUST select the onboard S/PDIF soundbar
   (`alsa_output.pci-0000_18_00.6.iec958-stereo` via `SINK_MATCH` /
   `CARD` in `audio.d/runewyrm-desk.conf`), not a Bluetooth or Jabra
   speaker.
1. Theater MUST use the GPU HDMI sink when present, with the stereo
   HDMI profile as fallback (`audio.d/runewyrm-stereo.conf`).
1. Workshare MUST use the same soundbar policy as desk.
1. Sink matching MUST be data from `audio.d`, not hostname `case`
   blocks inside `display-profile.sh`.

## Safety

1. Scripts MUST be host-safe: a laptop MUST NOT inherit runewyrm
   `DP-2` / `DP-3` / `HDMI-A-1` modes from a shared `monitors.conf`.
1. Unknown Hyprland connector names are ignored; explicit modes on
   shared names are not. Keep those modes out of the shared file.
1. `hyprctl keyword monitor` specs MUST strip a trailing `Hz` on the
   refresh field (`2560x1440@143.91`, not `@143.91Hz`).
1. Apply and idle MUST take `apply.lock` so overlapping binds and
   hypridle cannot interleave `keyword monitor`.
1. Watch stop MUST kill the process group of the PID file, then remove
   the PID file.
1. `monitors.d/default.conf` MAY keep a wildcard rule because it is only
   applied through `keyword monitor`, not sourced on reload.

## Commands

`display-switch.sh`:

| Arg                          | Behavior                                                        |
| ---------------------------- | --------------------------------------------------------------- |
| `restore` / `apply` / (none) | Reapply saved profile; start watch if single                    |
| `desk`                       | Stop watch; apply desk monitors + audio; save `desk`            |
| `single` / `hdmi`            | Detect panel; apply that profile; start watch                   |
| `<profile>`                  | Apply named profile; start or stop watch from `SINGLE_PROFILES` |
| `watch`                      | Foreground inotify loop (started via `setsid` only)             |
| `start-watch` / `stop-watch` | Lifecycle without changing profile                              |
| `status` / `detect`          | Diagnostics; no changes                                         |

`display-profile.sh`:

| Arg                                   | Behavior                               |
| ------------------------------------- | -------------------------------------- |
| `apply` / (none)                      | Reapply monitors for the saved profile |
| `<profile>`                           | Apply that monitor conf only           |
| `idle-off` / `idle-on` / `restore-ws` | Idle path                              |
| `status` / `list`                     | Diagnostics                            |

`display-audio.sh <profile>` MUST apply only that profile's sink.
