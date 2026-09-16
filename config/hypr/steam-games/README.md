# steam-games

Per-Steam-AppID overlays for `scripts/steam-proton-wrap.sh`.

The wrap script already follows the active Hyprland display profile
(`~/.local/state/hypr/display-profile` plus `conf.d/monitors.d/`). These
files only add title-specific Proton env and extra argv.

## Steam launch options

```bash
~/.config/hypr/scripts/steam-proton-wrap.sh %command%
```

The same line works on runewyrm and forgewyrm. The wrapper picks the
largest enabled output in the current profile:

| Host / profile        | Typical output | Mode used          |
| --------------------- | -------------- | ------------------ |
| runewyrm `desk`       | DP-3           | 3440x1440          |
| runewyrm `theater`    | HDMI-A-1       | live TV mode       |
| runewyrm `workshare`  | HDMI-A-1       | 2560x1440          |
| forgewyrm `default`   | eDP-1          | live panel mode    |

Force an output without changing the display profile:

```bash
STEAM_GAME_OUTPUT=HDMI-A-1 ~/.config/hypr/scripts/steam-proton-wrap.sh %command%
```

Disable Wine-Wayland for one title:

```bash
NO_PROTON_WAYLAND=1 ~/.config/hypr/scripts/steam-proton-wrap.sh %command%
```

## Overlay format

`steam-games/<SteamAppId>.conf` is sourced. Known keys:

| Key                                  | Meaning                                      |
| ------------------------------------ | -------------------------------------------- |
| `PROTON_ENABLE_WAYLAND`              | `1` / `0`                                    |
| `PROTON_FORCE_LARGE_ADDRESS_AWARE`   | `1` recommended for 32-bit titles            |
| `PROTON_USE_WOW64`                   | `1` recommended for 32-bit titles            |
| `INJECT_SIZE`                        | `1` appends `-w WIDTH -h HEIGHT` from live mode |
| `EXTRA_ARGS`                         | extra argv after `%command%`                 |

App ID comes from `SteamAppId`, `SteamGameId`, or `STEAM_COMPAT_APP_ID`.

Check what a launch would use:

```bash
~/.config/hypr/scripts/steam-proton-wrap.sh status
```
