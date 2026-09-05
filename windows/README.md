# windows

## Work developer box

Does not assume a home username, NAS shares, or a `D:\` git-home drive.

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\work-setup.ps1
```

That installs Windows Terminal, Git for Windows, and Oh My Posh, copies
`terminal-settings.json` into the Terminal settings location, and points
Git Bash `~/.bashrc` / `~/.bash_profile` at `git_bashrc.sh`.

Git Bash is the default Terminal profile. Look-and-feel is Tango Dark +
Lucida Sans Typewriter, which `config/kitty/kitty.conf` mirrors on Linux.

## Personal machine extras

`initial-admin-setup.ps1` and `user-setup.ps1` still hold home-specific
PATH and network drive maps. Do not run those on a work device.
