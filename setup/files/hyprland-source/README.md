# Hyprland source prefix

`install-hyprland-source` builds the Hyprland tag and hypr\* ecosystem
pins from `setup/versions.conf` into `/opt/hyprland`. Distro rpms stay
in `/usr`. Ly gets a second session named **Hyprland (source)**. The
desktop file Exec path is stable across tag bumps; re-running the
module overwrites the prefix in place.

This prefix is GCC 14 + libstdc++ + mold, matching OpenMandriva cooker
hyprland 0.56.2 / aquamarine. Distro Rock remains 0.48.1 in `/usr`.
BOINC and MakeMKV source builds still use `compiler.bashrc` clang.

Bump tags in `setup/versions.conf`. An already-exported env var still
wins for a one-off (`HYPRLAND_TAG=v0.56.2`). The stamp file under
`$PREFIX/share/hyprland-source/` records the last successful set.

## When distro Hyprland goes away

Goal: one stack in `/usr` (or `/usr/local`), stock Ly session `Hyprland`,
no `/opt/hyprland`. Remove the OpenMandriva hypr\* rpms **before**
installing the source tree into `/usr`, or cmake will keep linking Rock
`libhyprutils.so.5`.

Keep the Rock compile shims (GCC 14 `append_range` / `#embed` /
`string_view` / `pci.h` / glaze 8). Those are distro toolchain, not
dual-session.

### Host

- [ ] `dnf remove` the session rpms from `install-hyprland-session`
  (`hyprland`, `hyprland-qtutils`, `hypridle`, `hyprlock`,
  `hyprpicker`, `hyprpolkitagent`, `hyprcursor`,
  `xdg-desktop-portal-hyprland`). Leave `ly`, portals gtk, pipewire,
  mako, kitty.
- [ ] Confirm `/usr/bin/Hyprland` and `/usr/bin/hyprctl` are gone.
- [ ] Delete `/opt/hyprland` after the `/usr` install works.
- [ ] Delete `~/.cache/hyprland-source` if you do not need a rebuild
  cache.
- [ ] Remove `/usr/share/wayland-sessions/hyprland-source.desktop` and
  `/etc/ly/custom-sessions/hyprland-source.desktop`.
- [ ] Remove `/usr/lib/systemd/user/hyprsunset.service` if it still
  points at `/opt/hyprland/bin/hyprsunset` (cmake wrote that during
  the prefix build).
- [ ] Log in once with stock **Hyprland** in Ly. Pick that as the saved
  session.

### Installer (`install-hyprland-source.sh`)

- [ ] Default `PREFIX` to `/usr` (or `/usr/local`). Drop
  `HYPRLAND_SOURCE_PREFIX` unless you still want an override.
- [ ] Stamp under `/usr/share/hyprland-source/` or drop the stamp if
  rpm-style files are enough.
- [ ] Stop installing `start-hyprland-source` and
  `hyprland-source.desktop`. Stock `hyprland.desktop` `Exec=Hyprland`
  is enough.
- [ ] Stop calling `configure_ly_source_session` / writing
  `custom_sessions`.
- [ ] Drop `pin_prefix_hypr_link` (that rewrite exists to beat Rock
  `/usr/lib64/libhyprutils.so`).
- [ ] `CMAKE_PREFIX_PATH` / `CMAKE_LIBRARY_PATH` can stay `/usr` as
  normal.
- [ ] Do not install hypr\* cmake systemd units over `/usr` until the
  rpms are gone; then let them land in
  `/usr/lib/systemd/user/`.

### Dual-session machinery (delete)

- [ ] `config/hypr/scripts/hypr-session-exec.sh`
- [ ] `setup/files/hypr/hypridle.service.d/session-bin.conf`
- [ ] `setup/files/hypr/hyprpolkitagent.service.d/session-bin.conf`
- [ ] `setup/files/hypr/xdg-desktop-portal-hyprland.service.d/session-bin.conf`
- [ ] `setup/files/hypr/hyprsunset.service.d/session-bin.conf`
- [ ] Matching drop-ins under `~/.config/systemd/user/*.service.d/`
  (`session-bin.conf` only; keep
  `xdg-document-portal.service.d/timeout-stop.conf`)
- [ ] `setup/files/hyprland-source/start-hyprland-source.sh`
- [ ] `setup/files/hyprland-source/hyprland-source.desktop`
- [ ] `graphical-session.sh`: drop `HYPRLAND_SOURCE_PREFIX` from
  `SESSION_VARS`. Keep importing `WAYLAND_DISPLAY` /
  `HYPRLAND_INSTANCE_SIGNATURE`. `PATH` / `LD_LIBRARY_PATH` /
  `XDG_DATA_DIRS` import is optional once everything is `/usr`.
- [ ] `ensure_dropins` can stay for other drop-ins.

### `install-hyprland-session.sh` / roles

- [ ] Stop `ensure_packages` of `hyprland`, `hypridle`, `hyprlock`,
  `hyprpicker`, `hyprpolkitagent`, `hyprcursor`,
  `hyprland-qtutils`, `xdg-desktop-portal-hyprland`. Keep `ly`,
  `uwsm` only if still used, pipewire, mako, grim/slurp.
- [ ] Fold leftover session glue (ly enable, `hyprland-session.service`,
  drop-in glob) into one module, or keep this module as
  "login stack" without hypr rpms.
- [ ] `roles.conf`: one hyprland module per role, not session+source.

### Docs

- [ ] `AGENTS.md` Hyprland-from-source bullet (no `/opt`, no extra Ly
  session, installing into `/usr` is allowed once rpms are gone).
- [ ] `setup/README.md` "Hyprland from source" section.
- [ ] `config/hypr/README.md` graphical-session paragraph about
  `hypr-session-exec.sh`.
- [ ] This file.

### Config (Lua only)

The 0.48 `.conf` tree and 0.56 `hyprland.lua` tree are side by side until
this cutover. After distro Hyprland is gone:

- [ ] Delete `config/hypr/hyprland.conf` and `config/hypr/conf.d/*.conf`
  that Hyprland 0.48 parsed (`env.conf`, `monitors.conf`,
  `programs-autostart.conf`, `look-and-feel.conf`, `input.conf`,
  `keybinds.conf`, `window-rules.conf`).
- [ ] Keep `conf.d/monitors.d/`, `conf.d/hosts.d/`, and `conf.d/audio.d/`
  until those layouts are expressed in Lua (or stay as script-owned
  `KEY=value` / `monitor=` files that `display-profile.sh` reads).
- [ ] Convert `hypridle.conf` / `hyprlock.conf` only if those tools grow
  a Lua provider. They still use hyprlang on 0.56.

### Check after the cutover

- [ ] `command -v Hyprland hyprctl hypridle hyprlock hyprpaper` →
  `/usr/bin/...`
- [ ] `ldd $(command -v Hyprland)` NEEDED `libhyprutils` from `/usr/lib64`
  with the source SONAME (currently `.so.13`), not Rock `.so.5`.
- [ ] `systemctl --user cat hypridle.service` `ExecStart=/usr/bin/hypridle`
  (vendor unit, no session-bin drop-in).
- [ ] Ly shows one **Hyprland** entry.
- [ ] `astro-wallpaper.sh apply` talks to this `hyprctl` / `hyprpaper`.
