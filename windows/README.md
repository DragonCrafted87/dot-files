# windows

Kitty (`config/kitty/kitty.conf`) is the look-and-feel source on personal
machines. `terminal-settings.json` is the work-box Windows Terminal copy
of that same Tango Dark / Lucida setup.

Winget IDs live in `packages/*.list`. `install-packages.ps1` is the
idempotent installer, same idea as the Linux role modules.

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\install-packages.ps1 work
powershell -ExecutionPolicy Bypass -File .\windows\install-packages.ps1 personal
powershell -ExecutionPolicy Bypass -File .\windows\install-packages.ps1 work -Upgrade
```

## Work developer box

Does not assume a home username, NAS shares, or a `D:\` git-home drive.

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\work-setup.ps1
```

Bootstraps Git if needed, clones this repo, runs the work package list
(Windows Terminal, Git, Oh My Posh, VS Code), copies Terminal settings,
and points Git Bash `~/.bashrc` / `~/.bash_profile` at `git_bashrc.sh`.

From Git Bash later:

```bash
winget-install-packages work
winget-upgrade-packages work
```

## Personal machine extras

`initial-admin-setup.ps1` and `user-setup.ps1` still hold home-specific
PATH and network drive maps. Package installs should go through
`install-packages.ps1 personal` instead of the old bash arrays.
