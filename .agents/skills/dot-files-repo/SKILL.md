---
name: dot-files-repo
description: Use when placing a file in this repo, adding a config directory, or writing a shell helper.
---

# Dot files repo

## Clone

The checkout is `~/dot-files`. The user is `dragon`. The recorded clone
path is `~/.config/dot-files/root` (`DOTFILES_ROOT`). The saved Linux
role is `~/.config/dot-files/role`. Hostname checks use `hostname -s`
(`runewyrm`, `forgewyrm`, and the other wyrm hosts).

`main` is protected. A change goes on a feature branch.

## Trees

| Path           | Role                                                                                     |
| -------------- | ---------------------------------------------------------------------------------------- |
| `shell/`       | Linux, Git Bash, and root bashrc entrypoints, and the Oh My Posh theme                   |
| `bashrc.d/`    | Sourced snippets. This directory stays at the repo root                                  |
| `config/`      | Linked into `~/.config`                                                                  |
| `setup/`       | Role installer: `role.sh`, `roles.conf`, `modules/`, `files/`                            |
| `scripts/`     | User helpers such as ffmpeg and dictation. Roles do not install these                    |
| `setup/files/` | Files a role installs, such as udev rules, BOINC prefs, CUPS, and the pre-commit wrapper |
| `windows/`     | Winget lists and PowerShell                                                              |
| `docs/`        | Notes. Nothing here is executed                                                          |

`scripts/` and `setup/files/` stay separate directories. `docs/todo.md`
lists future work.

## Linker

`link-user-config.sh` links each directory under `config/` to
`~/.config/<dirname>`. A new app config is a directory there. Loose
files in `config/` are left unlinked. `config/Code` is not linked as a
whole tree. An existing real `~/.config/<name>` directory is left in
place.

## Shebang files

A file with a `#!` line has an extension that matches the interpreter
(`.sh`, `.py`, `.ps1`), except a file installed onto `PATH` as a
command name (`/usr/local/bin/boincmgr`, `~/.local/bin/brave-browser`).
Those installed names stay extensionless. A repo copy that is not the
installed name, such as a wrapper, a module, a helper, or an exec-once
script, keeps the extension. A role does not install a bare
`setup/files/foo` that has a shebang under the name `foo.sh`.

## Shell

`shell/linux.bashrc` sources `~/.bashrc.d/*.bashrc`, the symlink to
repo `bashrc.d/`. A new interactive helper is a function there. A
root-owned binary that a role must install, such as BOINC or
xbox-controller, is the case for `/usr/local/bin`.

`update-dot-files` pulls the repo and sources bashrc again.

## Secrets

Secrets stay out of git. `setup/utility/transfer-secrets.sh` moves them.
