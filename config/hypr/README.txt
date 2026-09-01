Hyprland 0.48 split config
==========================

Install
-------
1. Back up your current file:
     cp ~/.config/hypr/hyprland.conf ~/.config/hypr/hyprland.conf.bak

2. Copy this tree over:
     cp hyprland.conf ~/.config/hypr/hyprland.conf
     mkdir -p ~/.config/hypr/conf.d
     cp conf.d/*.conf ~/.config/hypr/conf.d/

3. Reload:
     hyprctl reload

If a sourced file is missing, Hyprland will error on reload. Paths are
absolute-style (~/.config/hypr/...) so it does not matter where you
edit from.

Layout
------
hyprland.conf                 orchestrator only (source= lines)
conf.d/env.conf               environment variables
conf.d/monitors.conf          display layout
conf.d/programs-autostart.conf  $vars + exec-once
conf.d/look-and-feel.conf     general / decoration / animations / dwindle / misc
conf.d/input.conf             keyboard, mouse, gestures
conf.d/keybinds.conf          binds
conf.d/window-rules.conf      window rules + xwayland

Animated border
---------------
col.active_border cycles:
  #305cde (blue) → #560591 (purple) → #780606 (red) → blue

animation = borderangle, 1, 80, linear, loop
  80 = 8 seconds per full rotation (speed is in deciseconds).

Tune in conf.d/look-and-feel.conf:
  Faster:  animation = borderangle, 1, 40, linear, loop
  Slower:  animation = borderangle, 1, 120, linear, loop
  Off:     animation = borderangle, 0

Note: style "loop" keeps Hyprland compositing at monitor refresh even
when idle. Fine on a desktop 144 Hz triple-head; turn it off if GPU
load or fans bother you.

Lua
---
Not needed. source= has existed for years and works on 0.48. You can
keep this layout after you upgrade; Lua is a later optional syntax.
