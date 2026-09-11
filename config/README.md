# config

Each **directory** here is linked to `~/.config/<dirname>` by
`setup/modules/link-user-config.sh`. Loose files in this folder are
ignored. Add a new app by dropping a folder; the next `update-role`
picks it up.

`Code/` is an exception. Only `User/settings.json`, `keybindings.json`,
and `snippets/` are linked by `configure-vscode`. Linking the whole
`~/.config/Code` tree would pull tokens out of globalStorage.

| Folder          | Destination                                                                              |
| --------------- | ---------------------------------------------------------------------------------------- |
| `hypr/`         | `~/.config/hypr` — Hyprland, hypridle, hyprlock, display profiles. See `hypr/README.md`. |
| `kitty/`        | `~/.config/kitty` — personal terminal look (source of truth vs Windows Terminal).        |
| `quickshell/`   | `~/.config/quickshell` — start menu / taskbar QML.                                       |
| `git/template/` | `~/.config/git/template` — `init.templatedir` hooks.                                     |
| `Code/User/`    | `~/.config/Code/User` files via `configure-vscode` (not a full-tree link).               |
