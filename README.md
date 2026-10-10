# dot-files

Personal Linux (OpenMandriva Rock) and Windows developer setup. One git
clone under `~/dot-files` is the source of truth. Role scripts install
packages and link configs. Re-running a role is the intended upgrade path.

Open work lives in the homelab parent at `docs/todo.md`
(`../docs/todo.md` from this checkout).

## Layout

| Path        | What it is                                                          |
| ----------- | ------------------------------------------------------------------- |
| `shell/`    | Linux and Git Bash entrypoints plus Oh My Posh theme.               |
| `bashrc.d/` | Function and alias snippets sourced by those entries.               |
| `config/`   | Trees linked into `~/.config/<name>` by the role.                   |
| `windows/`  | Winget lists and work/personal PowerShell. See `windows/README.md`. |
| `scripts/`  | One-off Python helpers (ffmpeg, dictation, Minecraft mods).         |
| `docs/`     | Notes that are not run by a role.                                   |
| `.pylintrc` | Pylint config (`pre-commit` passes `--rcfile=.pylintrc`).           |

## Linux machine

Fresh box that already has a user and sshd, from a working computer
that has the machine-setup checkout:

```bash
~/machine-setup/setup/init-remote.sh dragon@newbox.lan workstation
# then on the new box. init-remote.sh already wrote the role.
~/machine-setup/setup/role.sh
```

`init-remote.sh` writes the role file and the checkouts file, so
that command takes no role argument. On a workstation, `~/machine-setup`
is a symlink to `~/git-workspace/homelab/machine-setup`. On an htpc or
server, `~/machine-setup` is that machine's own clone. Later role
commands use that path:

```bash
~/machine-setup/setup/role.sh
~/machine-setup/setup/role.sh --enable-subrole laptop
```

Roles: `workstation`, `htpc`, `server`. Optional subroles (`laptop`,
`gaming`, `artifact-repo`, `nfs-server`) are saved on the box and
re-applied by `update-role`. Lists live in machine-setup
`setup/roles.conf`. `update-role` reads the checkouts file, fast-forwards
that machine-setup checkout when `git status` is clean, and runs
`setup/role.sh`. A dirty tree or a detached HEAD is left in place.

Later, on the machine itself:

```bash
update-dot-files          # git pull this repo, re-source bashrc
update-role               # fast-forward a clean machine-setup checkout, then re-run the saved role
update-role workstation   # set/save a role once if none is recorded
enable-subrole laptop     # apply once; later update-role keeps it
```

Saved state:

- `~/.config/dot-files/role` — last Linux role
- `~/.config/dot-files/subroles` — enabled subroles, one name per line
- `~/.config/dot-files/root` — path this shell was sourced from
- `~/.config/dot-files/checkouts` — absolute paths of the dot-files and machine-setup checkouts

## Windows machine

See `windows/README.md`. Short version for a work laptop:

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\work-setup.ps1
```

## pre-commit

`config/git/template` is the git init template (`init.templatedir`).
New clones get `hooks/pre-commit`. The hook calls the `pre-commit`
wrapper on PATH, which is a Docker image built by `install-python-dev`.
CI runs `.github/workflows/pre-commit.yml`.

```bash
pre-commit run
pre-commit run --all-files
git-update-pre-commit-hook   # copy the template hook into this repo
pre-commit-reset-cache       # wipe ~/.cache/pre-commit-docker
```
