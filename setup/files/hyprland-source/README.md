# Hyprland source install

`install-hyprland-source` builds the Hyprland tag and hypr\* ecosystem
pins from `setup/versions.conf` into `/usr/local` (`bin`, `lib64`,
`share`). The default prefix is not `/opt/hyprland`.
`HYPRLAND_SOURCE_PREFIX` still overrides that for a one-off.

Role reset removes the OpenMandriva `hyprland` rpm. Those names are not
in the ISO baseline, so `prune-extra-packages.py` already drops them.
The module does not run `dnf remove`.

If `rpm -q hyprland` still succeeds, the module logs the version and
exits 0. It does not build, and it does not write `/usr/local` or
`/opt/hyprland`.

When the package is gone, the module installs a Ly session named
**Hyprland** (`Exec=/usr/local/bin/Hyprland`) into
`/usr/share/wayland-sessions/hyprland.desktop` and
`/etc/ly/custom-sessions/hyprland.desktop`, and removes a leftover
`hyprland-source.desktop` from those two directories. It also links
`/usr/local/share/X11/xkb` at the system xkeyboard-config tree and
registers `/usr/local/lib64` with ldconfig. Binaries keep an rpath on
`/usr/local/lib64`. User units call `hypr-session-exec.sh`, which
selects `/usr/local`, a leftover `/opt/hyprland`, or `/usr` from the
running compositor.

`/usr` is not an install prefix. Do not point `HYPRLAND_SOURCE_PREFIX`
there.

After the first login from `/usr/local/bin/Hyprland`, delete a leftover
`/opt/hyprland` tree by hand. Delete `~/.cache/hyprland-source` only
when you do not want the rebuild cache.

## Still later

- Delete the 0.48 `hyprland.conf` tree, `spin-border.sh`, and
  `workstation-spin-border.service` once every host on this branch has
  been reset. Keep `conf.d/monitors.d/`, `conf.d/hosts.d/`,
  `conf.d/audio.d/`, `hypridle.conf`, and `hyprlock.conf`.
- Fold `install-hyprland-session` and `install-hyprland-source` into
  one `roles.conf` line once the session module is only Ly, portals,
  and user units.
