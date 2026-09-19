# Hyprland source prefix

`install-hyprland-source` builds Hyprland v0.56.2 and the listed hypr*
ecosystem pieces into `/opt/hyprland-0.56.2`. Distro rpms stay in
`/usr`. Ly gets a second session named **Hyprland (source 0.56.2)**.

Override prefix or tags with environment variables documented in the
module. Re-run the module after changing a tag; the stamp file under
`$PREFIX/share/hyprland-source/` records the last successful set.
