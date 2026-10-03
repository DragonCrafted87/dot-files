# Hostname display profiles for Hyprland

Behavioral rules for the scripts live in [`REQUIREMENTS.md`](REQUIREMENTS.md).
This file is the host map and operator cheat sheet.

The linked `~/.config/hypr` tree is shared across machines. Host-specific
layouts live in `conf.d/monitors.d/` and are the source of truth.
`display-profile.sh` applies `hyprctl keyword monitor` from those files.
`display-switch.sh` owns the saved profile and calls `display-audio.sh`.

Distro Hyprland 0.48.1 reads `hyprland.conf` and `conf.d/*.conf`. Source
0.56.2 reads `hyprland.lua` and `lua/*.lua` instead (it never opens the
`.conf` tree when the lua entry exists). Scripts, `hypridle.conf`, and
`hyprlock.conf` are shared.

Startup runs `display-switch.sh restore` once (`exec-once` /
`hyprland.start`). Reloads re-read `~/.local/state/hypr/monitors.runtime.conf`
from `lua/monitors.lua` (0.56) or `conf.d/monitors.conf` (0.48) so outputs
keep their last layout.

## Graphical session (systemd)

ly launches `Hyprland.desktop` (`Exec=/usr/local/bin/start-hyprland`
after the source install), not a UWSM session.
`graphical-session.target` has `RefuseManualStart=yes`, so a raw compositor
never reaches it and `WantedBy=graphical-session.target` units stay dead
(hypridle, hyprpolkitagent, mako, network-mounts).

`scripts/graphical-session.sh start` (exec-once) imports compositor env
(including `PATH` and `HYPRLAND_INSTANCE_SIGNATURE`) into the user
systemd and starts `hyprland-session.service`, which `BindsTo=` the
target. It does not import `LD_LIBRARY_PATH`; prefix libxkbcommon would
break kitty/qs. `exec-shutdown`
runs `stop` so session units go away with the compositor. Linger still
starts `default.target` at boot; that path must not claim a graphical
session.

uwsm is not installed. The source build passes `-DNO_UWSM=true`.
Its env preloader and `uwsm app` slices are more session manager than
this login needs. What we keep from that idea: graphical units stop
with the compositor, and linger services do not. `hyprland-session.service`
`PropagatesStopTo=` `graphical-session.target`. Role apps `PartOf=`
`workstation-session.target`, which `PartOf=` the graphical target.
`hypridle`, `hyprpolkitagent`, `mako`, and `hyprsunset` get the same
`PartOf=` from a user drop-in (the distro units already say it; the
drop-in keeps logout behavior if a package update drops the line).
`network-mounts.service` stays off that chain. Programs started from
binds (kitty, dolphin) stay children of Hyprland.

`hypridle`, `hyprpolkitagent`, `xdg-desktop-portal-hyprland`, and
`hyprsunset` use `scripts/hypr-session-exec.sh`. It runs `/usr/local/bin`
for a `/usr/local` compositor, `/opt/hyprland` for a leftover prefix,
and `/usr` for a distro session. `hyprsunset-times.py` rewrites
`hyprsunset.conf` from the built-in coordinates, or from `SUN_LAT` /
`SUN_LON` when the host file sets both. A weekly
user timer runs it, and session start runs it when that file is older
than seven days. Hyprsunset 0.4.0 only stores clock times.

Desk GUI apps are not Hyprland `exec-once` lines. They are child units of
`workstation-session.target` (WantedBy `graphical-session.target`): kitty,
Brave, Steam (`-silent` tray), Discord (`--start-minimized`),
`qs-startmenu` (`Restart=always`), spin-border (0.48 only; 0.56 uses
`borderangle` loop), Litra, KDE Connect.
HTPC extras use `htpc-session.target`. `enable-session-units.sh` enables
the target that matches `~/.config/dot-files/role`.

`xdg-document-portal.service` gets a user drop-in
(`TimeoutStopSec=5`, `TimeoutStopFailureMode=kill`) so logout does not
wait the default 90s on a stuck FUSE unmount of `/run/user/$UID/doc`.

```bash
systemctl --user status workstation-session.target
systemctl --user status qs-startmenu.service
```

```bash
~/.config/hypr/scripts/graphical-session.sh start
~/.config/hypr/scripts/graphical-session.sh status
~/.config/hypr/scripts/graphical-session.sh stop
```

File names:

- `monitors.d/<hostname>.conf` — single layout for that host
- `monitors.d/<hostname>-<profile>.conf` — named profiles (`desk`, ...)
- `monitors.d/default.conf` — fallback for unknown hosts
- `hosts.d/<hostname>.conf` — ports, idle output, HDMI-switch profile list
- `audio.d/<hostname>-<profile>.conf` — Pulse/PipeWire sink and card

`MATCH_DESC` in a monitor profile is matched (case-insensitive substring)
against `hyprctl monitors` description/make/model on `SWITCH_PORT`.

## Profiles (runewyrm)

| Profile     | File                      | Monitors                                           | Audio                         |
| ----------- | ------------------------- | -------------------------------------------------- | ----------------------------- |
| `desk`      | `runewyrm-desk.conf`      | DP-2 + DP-3 + HDMI-A-1 (AOC)                       | onboard S/PDIF soundbar       |
| `theater`   | `runewyrm-theater.conf`   | DP-2 and DP-3 disabled; HDMI ELMO MC1 1920x1080@60 | GPU HDMI 7.1, stereo fallback |
| `workshare` | `runewyrm-workshare.conf` | DP-2 and DP-3 disabled; HDMI AOC 2560x1440@143.91  | same soundbar as desk         |

Theater and workshare share `HDMI-A-1`. `SUPER+ALT+S` runs `single`,
which reads the panel currently on that port, picks theater (ELMO) or
workshare (AOC), and daemonizes `display-switch.sh watch`. That watcher
blocks on `inotifywait` for `/sys/class/drm/card0-HDMI-A-1/{status,edid}`
and re-selects the profile when the HDMI switch changes the panel.
`SUPER+ALT+D` (desk) kills the watcher. It is not an `exec-once` loop.

Desk still uses its own bind because that is the triple-head layout, not
"whatever is on HDMI."

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
~/.config/hypr/scripts/display-switch.sh restore
~/.config/hypr/scripts/display-switch.sh desk
~/.config/hypr/scripts/display-switch.sh single
~/.config/hypr/scripts/display-switch.sh status
```

Keybinds: `SUPER+ALT+D` desk, `SUPER+ALT+S` single (auto theater /
workshare from the HDMI-switch EDID).

`SUPER+[0-9]` runs `scripts/switch-workspace.py`. If that workspace is
already on a monitor, focus moves there. If it is hidden, the workspace
moves to the monitor under the cursor.

## Litra Glow

`scripts/litra-camera-lights.py` watches the Insta360 Link (`2e1a:*`)
and turns every USB Litra Glow (`046d:c900`) on while that camera has an
open V4L2 node. It waits 1.5s so a browser camera probe does not flash
the lamps. `workstation-litra.service` starts the watcher.

```bash
python3 ~/.config/hypr/scripts/litra-camera-lights.py status
python3 ~/.config/hypr/scripts/litra-camera-lights.py on
python3 ~/.config/hypr/scripts/litra-camera-lights.py off
```

hidraw access needs `setup/modules/desktop/configure-litra-glow.sh` (udev
rule plus the `video` group).

## Logitech G603 / G604

Windows G HUB on the work PC overwrites onboard ratbag profiles. A udev
rule starts the user oneshot `reset-ratbag-profile.service`, which runs
`scripts/reset-ratbag-profile.sh apply` and sets profile 0 through
`ratbagctl`. The same unit is enabled for `default.target` so login also
resets a mouse that was already plugged in.

Lightspeed child HID++ nodes (`046d:4085` G604, `046d:406c` G603) appear
after the `046d:c539` receiver. ratbagd ignores the receiver and only
enumerates initialized hidraw, so a GUI client can open against an empty
daemon. `hid-logitech-hidpp` bind starts `ratbagd-hidraw-rescan.service`,
which waits two seconds and replays hidraw ADD events. ratbagd also
gains an `ExecStartPost` udevadm trigger. Role module: `configure-ratbag`.

```bash
~/.config/hypr/scripts/reset-ratbag-profile.sh apply
~/.config/hypr/scripts/reset-ratbag-profile.sh status
reset-ratbag-profile
ratbag-status
```

IDs: Lightspeed receiver `046d:c539`, G603 `046d:406c` / Bluetooth
`046d:b01c`, G604 `046d:4085` / Bluetooth `046d:b024`. Override the match
or profile with `RATBAG_DEVICE_MATCH` and `RATBAG_PROFILE`.

## Astronomy wallpapers

`scripts/astro-wallpaper.py` downloads stills of nebulae, galaxies,
planets, comets, and clusters, then gives each enabled monitor its own
image through `hyprpaper`. Login runs `apply` (reuse today's cache).
A user timer at 06:30 refreshes the set. `display-switch.sh` waits for
the new layout, then re-applies so theater / workshare / desk each get
wallpapers. `hyprpaper.service` runs the daemon (`Restart=on-failure`)
through `hypr-session-exec.sh`. The timer is a oneshot and only restarts
that unit. Waking from idle runs `apply` again so a monitor that was
disabled at 06:30 gets a still. Files that are not JPEG/PNG/WebP (Wikimedia GIFs saved as
`.jpg`) are dropped; hyprpaper exits if it is asked to preload one.
A still whose border median luminance is at least
`ASTRO_WALLPAPER_MAX_BORDER` (default 200, on a 0–255 scale) is dropped.
That removes charts, diagrams, and scans on a near-white field. A bright
object on a dark field stays. `ffmpeg` reads the border. When `ffmpeg`
is not installed, the check is skipped and the still is kept.
hyprpaper 0.8 and newer gets `wallpaper { }` blocks. The 0.7
`wallpaper = MONITOR,path` lines leave every output with no target.

```bash
~/.config/hypr/scripts/astro-wallpaper.sh apply
~/.config/hypr/scripts/astro-wallpaper.sh refresh
~/.config/hypr/scripts/astro-wallpaper.sh status
astro-wallpaper-refresh
```

`SUPER+ALT+W` forces a new set. Cache lives in
`~/.cache/hypr/astro-wallpapers/`. Generated hyprpaper config is
`~/.local/state/hypr/hyprpaper.conf`. Optional `NASA_API_KEY` improves
APOD quota; Wikimedia Commons is the default pool. Role module:
`configure-astro-wallpaper`.

## Steam / Proton

`scripts/steam-proton-wrap.sh` is the shared launch wrapper. It reads the
saved display profile and aims Proton at the largest enabled output in
that layout, so the same Steam launch option works on the desk ultrawide,
the theater TV, and the laptop panel.

```bash
~/.config/hypr/scripts/steam-proton-wrap.sh %command%
```

Title-specific env lives in `steam-games/<SteamAppId>.conf`. See
`steam-games/README.md`. After `update-dot-files` the script is already
at `~/.config/hypr/scripts/` because this whole tree is linked.

Swap to theater first (`SUPER+ALT+S` with the ELMO on the switch), then
launch. The wrap script will see HDMI-only and use the live TV mode.

## Idle

`hypridle` calls the wrappers, which call the profile script:

- `idle-display-off.sh` → `display-profile.sh idle-off`, then `boinc-gpu idle`
- `idle-display-on.sh` → `display-profile.sh idle-on`, then `boinc-gpu active`

`boinc-gpu idle` sets BOINC GPU mode to `always`. `boinc-gpu active` sets
it to `never`. Login retries `active` until the client answers; logout
sets `idle`. Desktop prefs still say the GPU stays off while BOINC thinks
someone is at the machine. That idle timer does not move on Wayland, so
the display scripts are what actually start and stop GPU work. Role XML
is not swapped.

When `hosts.d/<host>.conf` sets `IDLE_MONITOR`, idle-off records
workspaces on that output and `dpms off` that output **and** `DESK_PORTS`
when those outputs are not `disable` in the active conf. It then disables
the idle monitor only if another output stays enabled (desk), so the TV
drops the link without leaving the compositor with zero `wl_output`s.
theater and workshare keep HDMI and only DPMS it: disabling the last
output crashes Brave, Quickshell, and the desktop portals. idle-on
`dpms on` the remaining ports, re-enables the idle monitor when it was
disabled, and restores those workspaces.

Hosts without `IDLE_MONITOR` just `dpms off` / `dpms on`.

Unlock and after-sleep run `idle-display-on.sh` so the desk comes back.
The 420s listener is what blanks HDMI.

If the DP panels are dark after a bad profile, `display-switch.sh desk`
brings them back.

## Audio

`scripts/display-audio.sh` reads `conf.d/audio.d/<host>-<profile>.conf`.
`display-switch.sh` calls it after the layout.

On runewyrm:

- desk / workshare → `alsa_output.pci-0000_18_00.6.iec958-stereo` (soundbar
  on onboard S/PDIF, not the Jabra)
- theater → Navi 31 HDMI 7.1 (`hdmi-surround71-extra3`), stereo fallback
- `stereo` → HDMI stereo for games that choke on 7.1; the Steam wrap
  restores the saved profile afterward

```bash
~/.config/hypr/scripts/display-audio.sh status
~/.config/hypr/scripts/display-audio.sh desk
```

## Hostname

The check is `hostname -s`. A FQDN like `runewyrm.stealthdragonland.net`
or `forgewyrm.example` still matches the short name.
