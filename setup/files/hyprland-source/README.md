# Hyprland source prefix

`install-hyprland-source` builds the Hyprland tag and hypr* ecosystem
pins from `setup/versions.conf` into
`/opt/hyprland-${HYPRLAND_SOURCE_VERSION}` (currently 0.56.2). Distro
rpms stay in `/usr`. Ly gets a second session named **Hyprland (source
0.56.2)**.

Bump tags in `setup/versions.conf`. An already-exported env var still
wins for a one-off (`HYPRLAND_TAG=v0.56.2`). Re-run the module after
changing a pin; the stamp file under `$PREFIX/share/hyprland-source/`
records the last successful set.
