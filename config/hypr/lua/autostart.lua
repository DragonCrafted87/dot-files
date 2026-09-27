-- Mirrors conf.d/programs-autostart.conf for Hyprland 0.56+.
-- Monitor layouts still come from display-switch.sh restore (hyprctl keyword).

hl.on("hyprland.start", function()
    hl.exec_cmd("~/.config/hypr/scripts/graphical-session.sh start")
    hl.exec_cmd("kbuildsycoca6 --noincremental")
    hl.exec_cmd("qs -c volume-osd -d -n")
    hl.exec_cmd("~/.config/hypr/scripts/astro-wallpaper.sh apply")
    hl.exec_cmd("~/.config/hypr/scripts/display-switch.sh restore")
end)

hl.on("hyprland.shutdown", function()
    hl.exec_cmd("~/.config/hypr/scripts/graphical-session.sh stop")
end)
