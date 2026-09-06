# Repo structure notes

Captured so these ideas are not lost in chat. None of the moves below
have been done yet.

## Why it feels off

Three eras sit next to each other. `setup/` is the coherent piece:
`role.sh` + `roles.conf` + `modules/` + `files/` + `utility/`.
`config/` auto-linking by directory name is the right rule.

The crowded repo root is the rest: ~~`hw_bashrc.sh`~~, ~~`git_bashrc.sh`~~,
~~`root_bashrc.sh`~~, ~~`profile`~~, ~~`omp.yaml`~~, ~~`pylintrc`~~,
~~`snippets.sh`~~ live beside `setup/` and `config/`.

Those shell entrypoints now live under `shell/`. `bashrc.d/` stays at
the repo root so `DOTFILES_ROOT` remains "parent of bashrc.d". Pylint
reads `.pylintrc` via `--rcfile=.pylintrc`.

## Possible later moves (not started)

- ~~`shell/linux.bashrc`, `shell/git-bash.bashrc`, `shell/root.bashrc`,
  `shell/profile`, `shell/omp.yaml`~~
- ~~Delete or park `snippets.sh` (typo, and it `return`s immediately —
  scratch pad, not product)~~
- ~~Keep `pylintrc` at root only if pre-commit expects it there~~
  (now `.pylintrc` + `--rcfile=.pylintrc`)

## Two script homes

`scripts/` is user helpers (ffmpeg, dictation). `setup/files/*/*.sh` are
installed by roles (mount-network, MakeMKV desktops, BOINC, pre-commit
wrapper). That split is fine. Do not merge them.

## bashrc.d vs Windows

`windows.bashrc` and `git_bashrc.sh` still assume `$HOME/dot-files`.
Linux records `DOTFILES_ROOT`. One later pass should make Git Bash use
the same recorded root.

## Hypr docs vs code

`config/hypr/conf.d/monitors.d/*.conf` exist, but live apply is
`hyprctl keyword` in `display-profile.sh`. Either generate keywords from
those files, or treat `monitors.d` as comments-only so they cannot drift.

## Package lists

Windows already has `windows/packages/*.list`. Linux packages are still
scattered through module scripts. Same pattern would be
`setup/files/packages/{common,workstation,laptop,htpc,server}.list`
consumed by the modules.

## ~~Duplicate update helper~~

~~`root_bashrc.sh` still has `update-dot-files` that `cd`s to
`~/dot-files`. User bash already has the smarter one in
`bashrc.d/setup.bashrc`. Root should call the same helper.~~

## Suggested order

1. ~~Kill `snippets.sh` or park it under `scripts/scratch/`.~~
1. ~~Point root `update-dot-files` at the bashrc.d function.~~
1. ~~Optional `shell/` folder for the three bashrc entrypoints + `profile`
   + `omp.yaml`.~~ Dropped `profile` (unused; PATH is in bashrc.d).
1. List-driven dnf packages, matching winget lists.
1. Single source for monitor layouts so `monitors.d` and
   `display-profile.sh` cannot disagree.

## Subdivide module scripts

`setup/modules/` is a flat list of ~35 scripts. Role membership is in
`roles.conf`, which is good, but the directory itself does not show
*why* a script exists.

A later split could be by job, still invoked as today
(`modules/<name>.sh` via a tiny lookup, or `modules/<area>/<name>.sh`
with `roles.conf` storing the basename):

```text
setup/modules/
  common/          # ssh, sudoers, repos, timezone, plasma removal
  desktop/         # hyprland, brave, flatpak, cups, gaming
  network/         # mounts, bluetooth
  compute/         # boinc, k3s, python-dev, makemkv
  host/            # configure-laptop / htpc / server leftovers
```

Keep one `lib.sh`. Do not put role names in the folder names — laptop
is already an overlay of workstation.

## Host sub-roles

Roles today are four buckets: workstation, laptop, htpc, server. Some
modules should run on **one machine** in a role, not every server.
`install-docker-image-manager` is the example: one box, not the whole
server fleet.

Idea: keep the four roles, then add optional host overlays in
`roles.conf`:

```ini
[server]
install-k3s
install-boinc
link-user-config
configure-server

# hostname -s match. Applied after the role section.
[host.castellan]
install-docker-image-manager

[host.calligraphy-wyrm]
# nas-only modules later
```

`role.sh` would run `[common]`, then `[workstation|...]`, then
`[host.$(hostname -s)]` when that section exists. Unknown hosts just
skip the overlay. That keeps Docker image manager off the other servers
without inventing a fifth top-level role.

Same pattern could pin MakeMKV-only quirks to runewyrm later if a laptop
should stay a workstation without optical-drive code paths.
