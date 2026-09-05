# Hostname display profiles for Hyprland

The linked `~/.config/hypr` tree is shared across machines. The old
`conf.d/monitors.conf` always loaded runewyrm's triple-head layout. This
split keeps that layout on **runewyrm** only and adds two live-swappable
profiles on that host.

## Profiles (runewyrm)

| Profile     | Monitors                                        | Audio                    |
| ----------- | ----------------------------------------------- | ------------------------ |
| `desk`      | DP-2 + DP-3 + HDMI-A-1, current 3-head layout   | restore last / desk sink |
| `theater`   | same DPs; HDMI-A-1 uses the TV's preferred mode | default sink → HDMI / TV |
| `workshare` | DP-2 and DP-3 **disabled**; HDMI stays          | restore desk sink        |

Every other hostname only gets `monitor=,preferred,highrr,auto`.

Last profile is remembered in `~/.local/state/hypr/display-profile` so it
survives reload and is applied at login. That path is outside the git-linked
config tree.

## Install

From the repo root, with `~/.config/hypr` already pointing at `config/hypr`:

```sh
cp artifacts-files/conf.d/monitors.conf          config/hypr/conf.d/monitors.conf
cp -r artifacts-files/conf.d/monitors.d          config/hypr/conf.d/
cp artifacts-files/scripts/display-profile.sh    config/hypr/scripts/display-profile.sh
cp artifacts-files/scripts/idle-display-off.sh   config/hypr/scripts/idle-display-off.sh
cp artifacts-files/scripts/idle-display-on.sh    config/hypr/scripts/idle-display-on.sh
chmod +x config/hypr/scripts/display-profile.sh \
         config/hypr/scripts/idle-display-off.sh \
         config/hypr/scripts/idle-display-on.sh
```

Append the three binds from `conf.d/keybinds-display-profiles.snippet` onto
`conf.d/keybinds.conf`.

Then:

```sh
hyprctl reload
~/.config/hypr/scripts/display-profile.sh status
```

## Swap profiles

```sh
~/.config/hypr/scripts/display-profile.sh desk
~/.config/hypr/scripts/display-profile.sh theater
~/.config/hypr/scripts/display-profile.sh workshare
```

or the keybinds:

- `SUPER+SHIFT+D` desk
- `SUPER+SHIFT+T` theater
- `SUPER+SHIFT+W` workshare

## Theater audio

The script uses `pactl` (pipewire-pulse). After the HDMI cable is on the TV:

```sh
pactl list short sinks
```

Pick the TV sink name (usually contains `hdmi`) and, if the default match is
wrong, either:

```sh
export THEATER_SINK_MATCH='hdmi'
export DESK_SINK_MATCH='analog'   # or usb / your DAC name
```

or edit the two `*_SINK_MATCH` values at the top of
`scripts/display-profile.sh`.

On `theater` the current default sink is saved, the HDMI sink becomes default,
and existing streams are moved. On `desk` / `workshare` that saved sink is
restored.

If several HDMI sinks exist, tighten the match to the exact name.

## Theater HDMI mode

`runewyrm-theater.conf` uses `preferred,auto` because the TV will not be
2560x1440@144. To lock a mode, change both:

- `conf.d/monitors.d/runewyrm-theater.conf`
- `apply_theater_monitors()` in `scripts/display-profile.sh`

Example: `HDMI-A-1,3840x2160@60,auto,1`

If you sit in the other room and want the desk panels off too, uncomment the
`DP-2/DP-3,disable` lines in `runewyrm-theater.conf` and do the same in
`apply_theater_monitors()`.

## workshare

`monitor=NAME,disable` removes those outputs from Hyprland so the work PC can
drive the two DisplayPort monitors. runewyrm keeps HDMI-A-1 at `0x0`.

Switch back with `desk` before you expect the DP panels on this machine again.

## Notes

- Guild Wars is still ruled to `8560x1440` in `window-rules.conf`. That only
  fits the desk layout.
- Idle wrappers only call the profile script:
  `idle-display-off.sh` → `display-profile.sh idle-off`
  `idle-display-on.sh` → `display-profile.sh apply`, then `dpms on`.
  On runewyrm, idle-off records every workspace on HDMI-A-1, blanks
  outputs, then disables HDMI-A-1 so a hotplug cannot wake the session.
  After HDMI is back, those workspaces are moved onto it again. If
  hyprlock is running, the move waits in the background until unlock —
  the layout itself is applied immediately so the password prompt still
  has a screen. Other hosts only get `dpms off`. The saved profile is
  not changed; idle-on reapplies it.
- `exec = display-profile.sh apply` re-asserts the saved profile on every
  `hyprctl reload`.
- Hostname check is `hostname -s` == `runewyrm`. If the box is actually
  `runewyrm.stealthdragonland.net`, `-s` still yields `runewyrm`.
