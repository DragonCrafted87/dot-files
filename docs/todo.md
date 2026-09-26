# Todo

Not scheduled.

## local builds

- current version of hyprland

## Git Bash clone path

- `shell/git-bash.bashrc` still sources `$HOME/dot-files/bashrc.d/*.bashrc`.
  Linux records `DOTFILES_ROOT` in `~/.config/dot-files/root`. Git Bash
  should use the same recorded root.
- `windows/work-setup.ps1` still sources
  `$HOME/dot-files/shell/git-bash.bashrc`.

## Linux package lists

- Windows already has `windows/packages/*.list`. Linux packages are still
  scattered through module `ensure_packages` calls. Same pattern would be
  `setup/files/packages/{common,workstation,laptop,htpc,server}.list`
  consumed by the modules.
- `setup/files/packages/iso-installed.txt` and `never-remove.list` are
  harvest/reset lists, not role package lists.
