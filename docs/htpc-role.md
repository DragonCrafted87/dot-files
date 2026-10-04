# HTPC role (hearthwyrm)

Paused 2026-09-26. Resume from this file; cabinet hardware is
[ht-cabinet.md](ht-cabinet.md).

`[htpc]` in `setup/roles.conf` still installs Hyprland, Brave, k3s, and
BOINC. `configure-htpc.sh` is still a stub. The desk session split is
done ([PR 59](https://github.com/DragonCrafted87/dot-files/pull/59)).

## Goal

Couch session on the cabinet NUC (**hearthwyrm**): Hyprland plus a
pad-first Quickshell home screen. Kodi for media/music, Steam gamepad
UI, DuckStation, PCSX2, and Brave with wvkbd. HDMI into the same ELMO
MC1 path as runewyrm theater.

## Locked choices

- Home screen: new Quickshell config `qs -c htpc` (large tiles). Hyprland
  stays the compositor.
- Kodi: one process at login, hidden/special workspace, JSON-RPC for
  music. Fullscreen UI only when the Kodi tile raises it. Kodi has no
  separate audio daemon; this is that behavior.
- Guide always toggles the launcher (`evsieve` virtual pad). Overlay
  open: dpad/ABXY go to the launcher only.
- Testing pad: Xbox Elite / pro pad in **Bluetooth** (xpadneo). Permanent
  couch pad is undecided. Spare 360 and One had exploded batteries.
- Wireless Adapter stays on runewyrm. `[htpc]` does not run
  `configure-xbox-controller` (xone). A 360 wireless pad needs the old
  360 PC receiver, or USB for a wired 360.
- Unplug the dongle before pairing the Elite on hearthwyrm. Same pad on
  dongle and Bluetooth at once fights itself.
- Emulators: DuckStation + PCSX2.
- On-screen keyboard: wvkbd, launcher control or Guide+Y.
- Graphical apps: systemd user units on `graphical-session.target`
  (`workstation-session.target` vs `htpc-session.target`). Shared Hyprland
  `exec-once` stays session plumbing (graphical-session bind, kbuildsycoca,
  wallpaper, volume-osd).
- Kodi addons: YouTube, Jellyfin, Amazon Prime, Curiosity Stream, FORMED,
  Pandora. Music stays on Jellyfin for now.
- k3s and BOINC stay on `[htpc]` until explicitly cut.
- runewyrm theater as a couch overlay is later, not the first host.

## Done

- Desk GUI apps are user units on `workstation-session.target`, not Hyprland autostart.
- `workstation-session.target` starts one unit per app. Steam `-silent`,
  Discord `--start-minimized`, `qs-startmenu.service` `Restart=always`.
- `htpc-session.target` exists as an empty placeholder.
- `enable-session-units.sh` enables the target for
  `~/.config/dot-files/role`.

## Architecture

```text
ly → Hyprland
        exec-once graphical-session.sh
        exec-once kbuildsycoca6
        exec-once astro-wallpaper apply

graphical-session.target
        hypridle, hyprpolkitagent, mako, network-mounts
        workstation-session.target   # saved role workstation
        htpc-session.target          # saved role htpc
```

Fill `htpc-session.target` with:

- `qs -c htpc` (`Restart=always`, same pattern as qs-startmenu)
- Kodi on `special:kodi`
- `htpc-guide.service` (evsieve)
- wvkbd installed, shown on toggle

Pad:

```text
Elite Bluetooth → hid_xpadneo → evsieve → virtual xpad
                                    Guide → qs -c htpc ipc launcher toggle
                                    overlay open → dpad/ABXY to launcher
```

Launcher tiles: Kodi, Steam, PS1, PS2, Brave, power. Music chrome on the
overlay (now playing, play/pause, skip) via Kodi JSON-RPC.

## Remaining PRs

### Host profile (hearthwyrm)

- `config/hypr/conf.d/monitors.d/hearthwyrm.conf` — single HDMI,
  1920x1080@60 first guess, `MATCH_DESC=ELMO` if the AVR EDID still says
  ELMO.
- `config/hypr/conf.d/hosts.d/hearthwyrm.conf` — `IDLE_MONITOR` on that
  HDMI.
- `config/hypr/conf.d/audio.d/hearthwyrm.conf` — NUC HDMI sink from
  `wpctl status` on the box (not runewyrm `pci-0000_03_00.1`).
- HTPC window rules (Kodi special workspace, Steam / DuckStation / PCSX2
  / Brave fullscreen) only when role is htpc. Hyprland cannot
  if-role; generate `~/.config/hypr/conf.d/runtime-role.conf` from
  `update-role`.

### Packages and Xbox Bluetooth

- `install-htpc-media.sh` — steam, gamescope, kodi (rpm or Flathub
  `tv.kodi.Kodi`), duckstation, pcsx2, wvkbd, evsieve. No MultiMC.
- `[htpc]` also runs `install-network-mounts` and a thin
  `configure-xbox-bluetooth.sh` (xpadneo half of `configure-xbox-controller`).
- Fill `configure-htpc.sh`: enable htpc units, kodi userdata skeleton,
  JSON-RPC, desktop files for tiles.

### Guide helper

- `htpc-guide.sh` + `htpc-guide.service`: evsieve map, Guide → qs IPC,
  overlay-open grab of dpad/ABXY.
- udev so Steam sees the virtual pad only.

### Quickshell launcher + Kodi hide/raise

- `config/quickshell/htpc/` (`ShellId` htpc). IPC `launcher toggle/open/close`.
- `kodi-session.sh raise|hide` via `hyprctl`.
- JSON-RPC client for now playing / pause / skip.
- If Kodi pauses when unmapped, keep it mapped off-screen or on a
  special workspace that still composites audio.

### Kodi addons + Brave/wvkbd

- `setup/files/kodi/` repo list + enable script. No vendored addon zips
  unless license-clean. Unofficial repos documented; first GUI pass
  allowed if a repo needs a key.
- Brave fullscreen; wvkbd layer + Guide+Y.

## Risks

- Unofficial Kodi streaming addons break; the role enables repos, it
  does not freeze addon versions in git.
- hearthwyrm HDMI sink name is unknown until the box is up.
- DuckStation/PCSX2 BIOS files stay off git.
- Steam Input can re-bind the physical pad if udev does not hide it.

## Out of scope until a later pass

- runewyrm theater using the htpc launcher
- moving music off Jellyfin onto a Kodi-native source
- taint the k3s agent `purpose=htpc:NoSchedule` for light jobs
- when the role is htpc and the system is active,
  `config/hypr/scripts/idle-display-on.sh` sets BOINC to no work and
  cordons k3s. The blanked path is
  `config/hypr/scripts/idle-display-off.sh`
- redesigning the workstation startmenu
