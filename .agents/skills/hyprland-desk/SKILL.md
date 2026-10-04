---
name: hyprland-desk
description: Use when changing Hyprland monitors, profiles, binds, workspaces, or desk session units.
---

# Hyprland desk

Host-specific detail is in `config/hypr/README.md` and
`config/hypr/REQUIREMENTS.md`.

## Files

The tree under `config/hypr` is shared. A host layout is a file.

- Monitors live in `conf.d/monitors.d/<host>.conf` or `<host>-<profile>.conf`.
- Ports, the HDMI switch, and idle output live in `conf.d/hosts.d/<host>.conf`.
- Audio for a profile lives in `conf.d/audio.d/<host>-<profile>.conf`.

`config/hypr/lua/` is the source of truth for binds. `conf.d/` is the
0.48 tree.

`display-profile.sh` applies `monitor=` lines with `hyprctl keyword`.
`display-switch.sh` owns the saved profile and calls `display-audio.sh`.
The last profile is `~/.local/state/hypr/display-profile`, and that file
is not in git. The exec-once restore runs once at login.

## Session units

Graphical desk apps start from `workstation-session.target`, one user
unit per app, on `graphical-session.target`. They do not start from
`programs-autostart.conf`. `qs-startmenu.service` uses `Restart=always`.
Steam starts with `-silent`. Discord starts with `--start-minimized`.
HTPC extras use `htpc-session.target`.

## runewyrm profiles

`desk` is the triple head plus the S/PDIF soundbar. `theater` is the
HDMI ELMO plus GPU HDMI 7.1. `workshare` is the HDMI AOC plus the
soundbar.

`SUPER+ALT+D` selects desk. `SUPER+ALT+S` selects the single-head
profile, theater or workshare from the HDMI EDID, and starts
`display-switch.sh watch`.

On desk and workshare the default sink is the onboard S/PDIF soundbar
`alsa_output.pci-0000_18_00.6.iec958-stereo`. Keyboard `XF86Audio*`
binds use `@DEFAULT_AUDIO_SINK@`.

## Workspaces

`SUPER+0-9` runs `python3 ~/.config/hypr/scripts/switch-workspace.py N`.
A visible workspace is focused on that monitor. A hidden workspace is
moved with `moveworkspacetomonitor` to the monitor under the cursor,
then focused.

`SUPER+D` then `1-5` focuses `code-1` through `code-5` on the monitor
that contains the middle of the enabled layout, or on the widest
monitor when none does. Headless outputs are left out of that layout.
`SUPER+SHIFT+D` then `1-5` sends the active window there. A new tiled
Code window takes the first of those workspaces that does not already
have one. Those chords exist in the Lua tree. On the 0.48 tree,
`SUPER+SHIFT+D` is still the desk profile.

The script filename is hyphenated. The file keeps
`# pylint: disable=invalid-name` at the top. Invoke it with `python3`.
