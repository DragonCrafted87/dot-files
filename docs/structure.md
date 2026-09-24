# Repo structure notes

## bashrc.d vs Windows

`windows.bashrc` and `git_bashrc.sh` still assume `$HOME/dot-files`.
Linux records `DOTFILES_ROOT`. One later pass should make Git Bash use
the same recorded root.

## Package lists

Windows already has `windows/packages/*.list`. Linux packages are still
scattered through module scripts. Same pattern would be
`setup/files/packages/{common,workstation,laptop,htpc,server}.list`
consumed by the modules.

## Subdivide module scripts

Done. Modules live under `setup/modules/<area>/`. `roles.conf` still
stores the basename; `find_module` in `lib.sh` looks the file up.

```text
setup/modules/
  common/          # ssh, sudoers, repos, timezone, plasma removal
  desktop/         # hyprland, brave, flatpak, cups, gaming
  network/         # mounts, bluetooth
  compute/         # boinc, k3s, python-dev, makemkv
  host/            # configure-laptop / htpc / server leftovers
```

Do not put role names in the folder names — laptop
is already an overlay of workstation.
