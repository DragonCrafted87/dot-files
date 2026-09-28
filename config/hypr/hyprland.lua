-- Hyprland 0.56+ entrypoint. Distro 0.48.1 ignores this file and reads
-- hyprland.conf. Do not require() the old .conf modules from here.
-- https://wiki.hypr.land/Configuring/Start/

require("lua/env")
require("lua/monitors")
require("lua/autostart")
require("lua/look-and-feel")
require("lua/input")
require("lua/keybinds")
require("lua/window-rules")
