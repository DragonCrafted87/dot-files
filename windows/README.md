# windows

Kitty (`config/kitty/kitty.conf`) is the look-and-feel source on personal
machines. `terminal-settings.json` is the work-box Windows Terminal copy
of that same Tango Dark / Lucida setup.

Winget IDs live in `packages/*.list`. `install-packages.ps1` is the
idempotent installer, same idea as the Linux role modules.

The last role used is written to `~/.config/dot-files/windows-role` so a
bare `winget-install-packages` / `winget-upgrade-packages` cannot silently
fall back to the other list.

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\install-packages.ps1 work
powershell -ExecutionPolicy Bypass -File .\windows\install-packages.ps1 personal
powershell -ExecutionPolicy Bypass -File .\windows\install-packages.ps1 -Upgrade
```

## Work developer box

Does not assume a home username, NAS shares, or a `D:\` git-home drive.

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\work-setup.ps1
```

Bootstraps Git if needed, clones this repo, runs the work package list
(Windows Terminal, Git, Oh My Posh, VS Code), copies Terminal settings,
points Git Bash `~/.bashrc` / `~/.bash_profile` at
`shell/git-bash.bashrc`, and saves the `work` role.

From Git Bash later:

```bash
windows-role              # print the saved role
winget-install-packages   # uses the saved role
winget-upgrade-packages   # uses the saved role
windows-role personal     # only if you really mean to switch this machine
```

## Personal machine extras

`initial-admin-setup.ps1` and `user-setup.ps1` still hold home-specific
PATH and network drive maps. Package installs should go through
`install-packages.ps1 personal` instead of the old bash arrays.
