# dot-files

Personal Linux (OpenMandriva Rock) and Windows developer setup. One git
clone under `~/dot-files` is the source of truth. Role scripts install
packages and link configs. Re-running a role is the intended upgrade path.

Layout ideas that are **not done yet** live in `docs/structure.md`.

## Layout

| Path        | What it is                                                          |
| ----------- | ------------------------------------------------------------------- |
| `shell/`    | Linux and Git Bash entrypoints plus Oh My Posh theme.               |
| `bashrc.d/` | Function and alias snippets sourced by those entries.               |
| `config/`   | Trees linked into `~/.config/<name>` by the role.                   |
| `setup/`    | OpenMandriva role installer. See `setup/README.md`.                 |
| `windows/`  | Winget lists and work/personal PowerShell. See `windows/README.md`. |
| `scripts/`  | One-off Python helpers (ffmpeg, dictation, Minecraft mods).         |
| `docs/`     | Notes that are not run by a role.                                   |
| `.pylintrc` | Pylint config (`pre-commit` passes `--rcfile=.pylintrc`).           |

## Linux machine

Fresh box that already has a user and sshd, from a working computer:

```bash
./setup/init-remote.sh dragon@newbox.lan workstation
# then on the new box:
~/dot-files/setup/role.sh workstation
```

Roles: `workstation`, `laptop` (workstation plus laptop extras), `htpc`,
`server`. Lists live in `setup/roles.conf`.

Later, on the machine itself:

```bash
update-dot-files          # git pull this repo, re-source bashrc
update-role               # re-run the saved role
update-role workstation   # set/save a role once if none is recorded
```

Saved state:

- `~/.config/dot-files/role` — last Linux role
- `~/.config/dot-files/root` — path to this clone (`DOTFILES_ROOT`)

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
