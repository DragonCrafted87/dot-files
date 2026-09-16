# steam-games

Per-Steam-AppID overlays for `scripts/steam-proton-wrap.sh`.

The wrap script follows the active Hyprland display profile. These files
only add title-specific Proton env, extra argv, or span mode.

## Steam launch options

```bash
~/.config/hypr/scripts/steam-proton-wrap.sh %command%
```

| Host / profile       | Default output | Span box when `SPAN=1`  |
| -------------------- | -------------- | ----------------------- |
| runewyrm `desk`      | DP-3 3440x1440 | 8560x1440 (three heads) |
| runewyrm `theater`   | HDMI live      | not used (one head)     |
| runewyrm `workshare` | HDMI 2560x1440 | not used (one head)     |
| forgewyrm `default`  | eDP-1 live     | not used (one head)     |

`SPAN=1` builds a bounding box from every enabled live output. Theater
and the laptop therefore stay single-screen automatically.

## Overlay format

`steam-games/<SteamAppId>.conf` is sourced. Optional `FAMILY=name` then
loads `steam-games/families/<name>.conf` first so Source / 32-bit titles
share one flag set.

| Key                                | Meaning                                             |
| ---------------------------------- | --------------------------------------------------- |
| `FAMILY`                           | shared overlay under `families/`                    |
| `SPAN`                             | `1` use combined desktop box when 2+ heads are live |
| `INJECT_SIZE`                      | append `-w WIDTH -h HEIGHT`                         |
| `EXTRA_ARGS`                       | extra argv after `%command%`                        |
| `PROTON_ENABLE_WAYLAND`            | `1` / `0`                                           |
| `PROTON_FORCE_LARGE_ADDRESS_AWARE` | 32-bit address space                                |
| `PROTON_USE_WOW64`                 | 32-bit Proton                                       |

Force one connector:

```bash
STEAM_GAME_OUTPUT=HDMI-A-1 ~/.config/hypr/scripts/steam-proton-wrap.sh %command%
```

Disable Wine-Wayland:

```bash
NO_PROTON_WAYLAND=1 ~/.config/hypr/scripts/steam-proton-wrap.sh %command%
```

## What has an overlay

Overlays exist only where Proton needs help. Factory / cozy titles with a
native build (Factorio, most sim games here) use wrap defaults and do not
get a file.

| AppID   | Title             | Why                   |
| ------- | ----------------- | --------------------- |
| 362890  | Black Mesa        | Source + `-oldgameui` |
| 70      | Half-Life         | Source family         |
| 280     | Half-Life: Source | Source family         |
| 220     | Half-Life 2       | Source family         |
| 340     | HL2 Lost Coast    | Source family         |
| 380     | HL2 Episode One   | Source family         |
| 420     | HL2 Episode Two   | Source family         |
| 400     | Portal            | Source family         |
| 620     | Portal 2          | Source family         |
| 1091500 | Cyberpunk 2077    | `SPAN=1`              |
| 46270   | Star Wolves       | legacy 32-bit         |

Add `SPAN=1` to another title if you want the same desk-triple behaviour.
