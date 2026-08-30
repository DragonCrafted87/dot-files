Hyprland 0.48 split config
==========================

Install
-------
1. Back up your current file:
     cp ~/.config/hypr/hyprland.conf ~/.config/hypr/hyprland.conf.bak

2. Copy this tree over:
     cp hyprland.conf ~/.config/hypr/hyprland.conf
     mkdir -p ~/.config/hypr/conf.d ~/.config/hypr/scripts
     cp conf.d/*.conf ~/.config/hypr/conf.d/
     cp scripts/spin-border.sh ~/.config/hypr/scripts/
     chmod +x ~/.config/hypr/scripts/spin-border.sh

3. Reload (exec-once lines only run on a new session):
     hyprctl reload
     ~/.config/hypr/scripts/spin-border.sh &

If a sourced file is missing, Hyprland will error on reload.

Layout
------
hyprland.conf                   orchestrator only (source= lines)
conf.d/env.conf                 environment variables
conf.d/monitors.conf            display layout
conf.d/programs-autostart.conf  $vars + exec-once
conf.d/look-and-feel.conf       general / decoration / animations / dwindle / misc
conf.d/input.conf               keyboard, mouse, gestures
conf.d/keybinds.conf            binds
conf.d/window-rules.conf        window rules + xwayland
scripts/spin-border.sh          0.48 border spin workaround

Animated border
---------------
Native `animation = borderangle, ..., loop` is broken on Hyprland
0.47–0.48: the gradient makes one full turn and then freezes. That is
a compositor bug (#9251 / #9313), not a config typo.

Workaround: scripts/spin-border.sh walks the gradient angle through
hyprctl. Speed is SECONDS_PER_TURN at the top of the script (default 8).

When a newer Hyprland actually honors loop again, drop the script and
switch look-and-feel.conf back to:

  animation = borderangle, 1, 80, linear, loop

Lua
---
Not needed. source= has existed for years and works on 0.48.
