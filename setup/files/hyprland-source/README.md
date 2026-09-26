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
