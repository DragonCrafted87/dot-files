# Hostname display profiles for Hyprland

The linked `~/.config/hypr` tree is shared across machines. Host-specific
layouts live in `conf.d/monitors.d/` and are applied by
`scripts/display-profile.sh`. A laptop never inherits runewyrm's
triple-head layout from disk.

Startup applies the last profile once (`exec-once`). Reloads do not
re-run apply, so `keyword monitor` cannot loop the compositor.

## Profiles (runewyrm)

| Profile     | Monitors                                  | Audio                     |
| ----------- | ----------------------------------------- | ------------------------- |
| `desk`      | DP-2 + DP-3 + HDMI-A-1                    | restore last / desk sink  |
| `theater`   | same DPs; HDMI uses the TV preferred mode | default sink to HDMI / TV |
| `workshare` | DP-2 and DP-3 disabled; HDMI stays        | restore desk sink         |

Every other hostname only gets `monitor=,preferred,highrr,auto`.

Last profile is stored in `~/.local/state/hypr/display-profile` (outside
the git-linked tree).

## Swap profiles

```bash
~/.config/hypr/scripts/display-profile.sh desk
~/.config/hypr/scripts/display-profile.sh theater
~/.config/hypr/scripts/display-profile.sh workshare
~/.config/hypr/scripts/display-profile.sh status
```

Keybinds: `SUPER+SHIFT+D` desk, `SUPER+SHIFT+T` theater,
`SUPER+SHIFT+W` workshare.

## Idle

`hypridle` calls the wrappers, which call the profile script:

- `idle-display-off.sh` → `display-profile.sh idle-off`
- `idle-display-on.sh` → `dpms on`, then `display-profile.sh idle-on`

On runewyrm, idle-off records workspaces on HDMI-A-1 and disables that
output only. Desk DisplayPort panels stay as they are. idle-on re-enables
HDMI for the saved profile and restores those workspaces. It does not
rewrite DP-2/DP-3. Other hosts only get `dpms off` / `dpms on`.

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

The check is `hostname -s` == `runewyrm`. A FQDN like
`runewyrm.stealthdragonland.net` still matches.
