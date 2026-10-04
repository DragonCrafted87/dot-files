---
name: desk-devices
description: Use when changing desk audio, the Jabra, Litra Glow, the Insta360 Link, the G604, or wallpapers.
---

# Desk devices

PipeWire is 1.4.x with WirePlumber. The volume CLI is `wpctl`.

## Hardware on runewyrm

| Device                    | Where                                                        |
| ------------------------- | ------------------------------------------------------------ |
| Desk soundbar             | Onboard S/PDIF, default sink                                 |
| Jabra Speak 710           | USB full-speed `5-2.1`, calls                                |
| Insta360 Link             | USB high-speed `5-2.2`, V4L2 `/dev/video0`, MJPG             |
| Litra Glow pair           | USB `5-2.3` and `5-2.4`, `046d:c900`                         |
| Logitech G604 pair        | Lightspeed `046d:c539`, device `046d:4085`                   |
| Valve Index and 3D camera | The other controller (`16:00.0`). Leave it out of desk calls |

## Jabra Speak 710

The headset sits on runewyrm USB hub `0000:18:00.3-2.1` at full speed,
`0b0e:2475`. It uses the analog profile and `PCM` mixer 0-11. Discord
WebRTC call audio plays to this sink. Desk media stays on the soundbar.

`bashrc.d/jabra.bashrc` defines `jabra-volume`, `jabra-mute`, and
`jabra-unmute`. `jabra-volume` takes a level such as `50` or `100`.
Those functions target the Jabra PipeWire sink and source. Jabra
buttons stay off the default sink.

The desk default sink is the soundbar, and the keyboard volume keys
stay there. Grabbing the Jabra evdev node (`EVIOCGRAB`) would take
those keys off the soundbar.

While Discord streams the Insta360 Link at `5-2.2` on the same Realtek
hub, the 710 hardware pads often stop affecting volume on Linux. The
same dock still works on Windows. Those pads have no evdev or hidraw
report. The Insta360 also exposes an ALSA card. That card is not the
default audio source.

## Litra Glow and the Insta360 Link

`scripts/litra-camera-lights.py watch` starts from
`workstation-litra.service`. It turns every USB Litra Glow on while
the Insta360 Link (`2e1a:*`) has an open V4L2 node. The debounce is
1.5 seconds, so a browser probe does not flash the lamps.

## Logitech G603 and G604

Windows G HUB on the work computer overwrites onboard profiles. A udev
rule starts `reset-ratbag-profile.service`, which sets ratbag profile 0
through `ratbagctl`. When hid-logitech-hidpp binds, it also starts
`ratbagd-hidraw-rescan.service`, so ratbagd retries Lightspeed child
nodes that were missing at daemon start. The role module is
`configure-ratbag`.

## Astronomy wallpapers

`astro-wallpaper.sh apply` runs at login. The daily timer at 06:30 runs
`refresh`. `display-switch.sh` applies the set again after a layout
change. Each enabled monitor gets one still from `hyprpaper.service`
(`Restart=on-failure`), started through `hypr-session-exec.sh`. The
daily timer exits when refresh finishes and tears down processes it
started, so the timer restarts that unit and does not spawn hyprpaper
itself. `SUPER+ALT+W` forces a new set.
