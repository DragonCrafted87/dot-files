# Hostname display profiles for Hyprland

The linked `~/.config/hypr` tree is shared across machines. Host-specific
layouts live in `conf.d/monitors.d/` and are the source of truth.
`scripts/display-profile.sh` parses those files and applies `hyprctl keyword monitor` so a laptop never inherits runewyrm's triple-head
layout from `monitors.conf` on disk.

Startup applies the last profile once (`exec-once`). Reloads do not
re-run apply, so `keyword monitor` cannot loop the compositor. A
background `watch` job then follows HDMI-switch EDID while a single-output
profile is active.

File names:

- `monitors.d/<hostname>.conf` — single layout for that host
- `monitors.d/<hostname>-<profile>.conf` — named profiles (`desk`, ...)
- `monitors.d/default.conf` — fallback for unknown hosts
- `hosts.d/<hostname>.conf` — ports, idle output, HDMI-switch profile list
- `audio.d/<hostname>-<profile>.conf` — Pulse/PipeWire sink and card

`MATCH_DESC` in a monitor profile is matched (case-insensitive substring)
against `hyprctl monitors` description/make/model on `SWITCH_PORT`.

## Profiles (runewyrm)

| Profile     | File                      | Monitors                                            | Audio                          |
| ----------- | ------------------------- | --------------------------------------------------- | ------------------------------ |
| `desk`      | `runewyrm-desk.conf`      | DP-2 + DP-3 + HDMI-A-1 (AOC)                        | onboard S/PDIF soundbar        |
| `theater`   | `runewyrm-theater.conf`   | DP-2 and DP-3 disabled; HDMI ELMO MC1 1920x1080@60  | GPU HDMI 7.1, stereo fallback  |
| `workshare` | `runewyrm-workshare.conf` | DP-2 and DP-3 disabled; HDMI AOC 2560x1440@143.91   | same soundbar as desk          |

Theater and workshare share `HDMI-A-1`. `SUPER+SHIFT+T` runs `single`,
which reads the panel currently on that port and picks theater (ELMO) or
workshare (AOC). Flipping the HDMI switch while already in one of those
profiles does the same thing automatically.

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
~/.config/hypr/scripts/display-profile.sh desk
~/.config/hypr/scripts/display-profile.sh single
~/.config/hypr/scripts/display-profile.sh theater
~/.config/hypr/scripts/display-profile.sh workshare
~/.config/hypr/scripts/display-profile.sh apply
~/.config/hypr/scripts/display-profile.sh status
```

Keybinds: `SUPER+SHIFT+D` desk, `SUPER+SHIFT+T` single (auto theater /
workshare from the HDMI-switch EDID).

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

Swap to theater first (`SUPER+SHIFT+T` with the ELMO on the switch), then
launch. The wrap script will see HDMI-only and use the live TV mode.

## Idle

`hypridle` calls the wrappers, which call the profile script:

- `idle-display-off.sh` → `display-profile.sh idle-off`, then
  `boinc-session.sh idle`
- `idle-display-on.sh` → `dpms on`, `display-profile.sh idle-on`, then
  `boinc-session.sh active`

`boinc-session.sh` retargets
`~/.var/app/edu.berkeley.BOINC/global_prefs_override.xml` at the repo
file `setup/files/boinc/prefs/<role>.xml` or `<role>-idle.xml` and tells
the client to reread it. Edit those XML files in git; do not copy them
under `/etc`.

When `hosts.d/<host>.conf` sets `IDLE_MONITOR`, idle-off records
workspaces on that output, `dpms off` that output **and** `DESK_PORTS`
when those outputs are not `disable` in the active conf, then disables
the idle monitor so the TV drops the link. idle-on `dpms on` the desk
ports only when the active conf leaves them enabled, re-enables the idle
monitor using the line from that conf, and restores those workspaces.
theater and workshare leave the desk DPs disabled.

Hosts without `IDLE_MONITOR` just `dpms off` / `dpms on`.

Unlock and after-sleep run `idle-display-on.sh` so the desk and the
active BOINC caps come back together. The 420s listener is what blanks
HDMI and switches BOINC to idle prefs.

If the DP panels are dark after a bad profile, `display-profile.sh desk`
brings them back.

## Audio

`scripts/display-audio.sh` reads `conf.d/audio.d/<host>-<profile>.conf`.
`display-profile.sh` sources it and applies audio after the layout.

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
