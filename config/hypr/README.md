# Hostname display profiles for Hyprland

The linked `~/.config/hypr` tree is shared across machines. Host-specific
layouts live in `conf.d/monitors.d/` and are the source of truth.
`scripts/display-profile.sh` parses those files and applies `hyprctl keyword monitor` so a laptop never inherits runewyrm's triple-head
layout from `monitors.conf` on disk.

Startup applies the last profile once (`exec-once`). Reloads do not
re-run apply, so `keyword monitor` cannot loop the compositor.

File names:

- `monitors.d/<hostname>.conf` — single layout for that host
- `monitors.d/<hostname>-<profile>.conf` — named profiles (`desk`, ...)
- `monitors.d/default.conf` — fallback for unknown hosts

## Profiles (runewyrm)

| Profile     | File                      | Monitors                                            | Audio                     |
| ----------- | ------------------------- | --------------------------------------------------- | ------------------------- |
| `desk`      | `runewyrm-desk.conf`      | DP-2 + DP-3 + HDMI-A-1                              | restore last / desk sink  |
| `theater`   | `runewyrm-theater.conf`   | DP-2 and DP-3 disabled (other room); HDMI / TV only | default sink to HDMI / TV |
| `workshare` | `runewyrm-workshare.conf` | DP-2 and DP-3 disabled; HDMI stays at desk mode     | restore desk sink         |

## Profiles (forgewyrm)

| Profile   | File             | Monitor | Mode           | Scale | Logical size |
| --------- | ---------------- | ------- | -------------- | ----- | ------------ |
| `default` | `forgewyrm.conf` | eDP-1   | 3840x2400@60Hz | 1.5   | 2560x1600    |

Scale 1.5 keeps the native 16:10 framebuffer and makes UI size match a
2560x1600 (16:10 2K) panel. Scale 2.0 would look like 1920x1200.

Every other hostname uses `default.conf`.

Last profile is stored in `~/.local/state/hypr/display-profile` (outside
the git-linked tree).

## Swap profiles

```bash
~/.config/hypr/scripts/display-profile.sh desk
~/.config/hypr/scripts/display-profile.sh theater
~/.config/hypr/scripts/display-profile.sh workshare
~/.config/hypr/scripts/display-profile.sh apply
~/.config/hypr/scripts/display-profile.sh status
```

Keybinds: `SUPER+SHIFT+D` desk, `SUPER+SHIFT+T` theater,
`SUPER+SHIFT+W` workshare.

## Idle

`hypridle` calls the wrappers, which call the profile script:

- `idle-display-off.sh` → `display-profile.sh idle-off`
- `idle-display-on.sh` → `dpms on`, then `display-profile.sh idle-on`

On runewyrm, idle-off records workspaces on HDMI-A-1, `dpms off` that
output **and** DP-2/DP-3 when those outputs are not `disable` in the
active conf, then disables HDMI so the TV drops the link. idle-on
`dpms on` the DP panels only when the active conf leaves them enabled,
re-enables HDMI using the HDMI line from that conf, and restores those
workspaces. theater and workshare leave the desk DPs disabled.

Lock and unlock also run the same off/on pair (`on_lock_cmd` /
`on_unlock_cmd`) so the desk blanks when hyprlock starts, not only after
the 420s idle timer.

If the DP panels are dark after a bad profile, `display-profile.sh desk`
brings them back.

## Theater audio

Uses `pactl`. After the HDMI cable is on the TV:

```bash
pactl list short sinks
export THEATER_SINK_MATCH='hdmi'
export DESK_SINK_MATCH='analog'
```

or edit `*_SINK_MATCH` at the top of `scripts/display-profile.sh`.

## Hostname

The check is `hostname -s`. A FQDN like `runewyrm.stealthdragonland.net`
or `forgewyrm.example` still matches the short name.
