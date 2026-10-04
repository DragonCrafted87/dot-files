# Hyprland source prefix

`install-hyprland-source` builds the Hyprland tag and hypr\* ecosystem
pins from `setup/versions.conf` into `/usr/local`. Role reset removes
the distro hypr rpms. Ly uses the stock session name **Hyprland**,
from `/usr/share/wayland-sessions/hyprland.desktop`, with
`Exec=/usr/local/bin/start-hyprland`. Re-running the module overwrites
`/usr/local` in place. `HYPRLAND_SOURCE_PREFIX` is only a one-off
override.

This build is GCC 14 + libstdc++ + mold, matching OpenMandriva cooker
hyprland 0.56.2 / aquamarine. BOINC and MakeMKV source builds still
use `compiler.bashrc` clang.

Bump tags in `setup/versions.conf`. An already-exported env var still
wins for a one-off (`HYPRLAND_TAG=v0.56.2`). The stamp file under
`/usr/local/share/hyprland-source/` records the last successful set.

## When the stack moves to `/usr`

The running install is `/usr/local`. Do not point this module's prefix
at `/usr` while OpenMandriva packages still own that tree. cmake will
link Rock `libhyprutils.so.5` if those rpms are present.

Keep the Rock compile shims (GCC 14 `append_range` / `#embed` /
`string_view` / `pci.h` / glaze 8). Those are distro toolchain, not
dual-session.

- [ ] Build an rpm that installs this stack into `/usr` once a package
  repo exists. Until that package exists, the prefix stays `/usr/local`.

### Host

- [x] Confirm `/usr/bin/Hyprland` and `/usr/bin/hyprctl` are gone.
- [x] Delete `/opt/hyprland` after the `/usr/local` install works.
- [ ] Delete `~/.cache/hyprland-source` if you do not need a rebuild
  cache.
- [x] Remove `/usr/share/wayland-sessions/hyprland-source.desktop` and
  `/etc/ly/custom-sessions/hyprland-source.desktop`.
- [x] Remove `/usr/lib/systemd/user/hyprsunset.service` if it still
  points at `/opt/hyprland/bin/hyprsunset` (cmake wrote that during
  the prefix build).

### Installer (`install-hyprland-source.sh`)

- [x] Default `PREFIX` to `/usr/local`. Keep `HYPRLAND_SOURCE_PREFIX`
  as a one-off override.
- [ ] Move the stamp to `/usr/share/hyprland-source/` with the rpm, or
  drop it if the package owns the files. Today it lives under
  `/usr/local/share/hyprland-source/`.
- [x] Stop installing `start-hyprland-source` and
  `hyprland-source.desktop`. Stock `hyprland.desktop` `Exec` is
  `/usr/local/bin/start-hyprland`.
- [x] Stop calling `configure_ly_source_session` / writing
  `custom_sessions`.
- [x] Drop `pin_prefix_hypr_link` (that rewrite exists to beat Rock
  `/usr/lib64/libhyprutils.so`).
- [x] `CMAKE_PREFIX_PATH` / `CMAKE_LIBRARY_PATH` stay `/usr/local`.
- [x] Leave hypr\* cmake systemd units out of `/usr`. The rpm can
  install them under `/usr/lib/systemd/user/`.

### Dual-session machinery (delete)

- [x] `config/hypr/scripts/hypr-session-exec.sh`
- [x] `setup/files/hypr/hypridle.service.d/session-bin.conf`
- [x] `setup/files/hypr/hyprpolkitagent.service.d/session-bin.conf`
- [x] `setup/files/hypr/xdg-desktop-portal-hyprland.service.d/session-bin.conf`
- [x] `setup/files/hypr/hyprsunset.service.d/session-bin.conf`
- [x] Matching drop-ins under `~/.config/systemd/user/*.service.d/`
  (`session-bin.conf` only; keep
  `xdg-document-portal.service.d/timeout-stop.conf`)
- [x] `setup/files/hyprland-source/start-hyprland-source.sh`
- [x] `setup/files/hyprland-source/hyprland-source.desktop`
- [x] `graphical-session.sh`: drop `HYPRLAND_SOURCE_PREFIX` from
  `SESSION_VARS`. Keep importing `WAYLAND_DISPLAY` /
  `HYPRLAND_INSTANCE_SIGNATURE`. `PATH` / `LD_LIBRARY_PATH` /
  `XDG_DATA_DIRS` import is optional once everything is `/usr/local`
  (and `/usr` after the rpm).
- [x] `ensure_dropins` can stay for other drop-ins.

### `install-hyprland-session.sh` / roles

- [x] Stop `ensure_packages` of `hyprland`, `hypridle`, `hyprlock`,
  `hyprpicker`, `hyprpolkitagent`, `hyprcursor`,
  `hyprland-qtutils`, `xdg-desktop-portal-hyprland`. Keep `ly`,
  `uwsm` only if still used, pipewire, mako, grim/slurp.
  Drop `pavucontrol-qt` (`hyprpwcenter` is the volume UI).
- [x] `config/hypr/scripts/session-control.sh`: drop the fallback that
  runs when `hyprshutdown` is not on `PATH`.
- [ ] If hyprsunset accepts `time = sunrise`, delete
  `hyprsunset-times.py`, `hyprsunset-times.service`,
  `hyprsunset-times.timer`, and the generated `hyprsunset.conf`. Put
  latitude and longitude in the config instead.
- [x] Fold leftover session glue (ly enable, `hyprland-session.service`,
  drop-in glob) into one module, or keep this module as
  "login stack" without hypr rpms.

### Docs

- [x] `AGENTS.md` Hyprland-from-source bullet (no `/opt`, no extra Ly
  session, install prefix `/usr/local`).
- [x] `setup/README.md` "Hyprland from source" section.
- [x] `config/hypr/README.md` graphical-session paragraph about
  `hypr-session-exec.sh`.
- [x] This file.

### Config (Lua only)

Hyprland reads `hyprland.lua`. Host layouts stay script-owned files.
`hypridle.conf` and `hyprlock.conf` stay hyprlang until those tools grow
a Lua provider.

- [x] Delete `config/hypr/hyprland.conf` and `config/hypr/conf.d/*.conf`
  that Hyprland 0.48 parsed (`env.conf`, `monitors.conf`,
  `programs-autostart.conf`, `look-and-feel.conf`, `input.conf`,
  `keybinds.conf`, `window-rules.conf`).
- [x] Keep `conf.d/monitors.d/`, `conf.d/hosts.d/`, and `conf.d/audio.d/`
  until those layouts are expressed in Lua (or stay as script-owned
  `KEY=value` / `monitor=` files that `display-profile.sh` reads).
- [ ] Convert `hypridle.conf` / `hyprlock.conf` only if those tools grow
  a Lua provider. They still use hyprlang on 0.56.
- [x] Delete `scripts/spin-border.sh` and
  `setup/files/hypr/workstation-spin-border.service`. Source 0.56
  uses `borderangle` `loop` in `lua/look-and-feel.lua`.

### Check after the cutover

- [x] `command -v Hyprland hyprctl hypridle hyprlock hyprpaper` →
  `/usr/local/bin/...` (`/usr/bin/...` after the rpm).
- [x] `ldd $(command -v Hyprland)` NEEDED `libhyprutils` from
  `/usr/local/lib64` with the source SONAME (currently `.so.13`), not
  Rock `.so.5`.
- [x] `systemctl --user cat hypridle.service` `ExecStart` uses
  `/usr/local/bin/hypridle` (`/usr/bin/hypridle` after the rpm), with
  no session-bin drop-in.
- [x] Ly shows one **Hyprland** entry.
- [x] `astro-wallpaper.sh apply` talks to this `hyprctl` / `hyprpaper`.
