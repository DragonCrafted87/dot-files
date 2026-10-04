-- Session start and shutdown. Monitor restore is display-switch.sh.

local captureSo = "/usr/local/lib/libhyprcapture.so"

hl.config({
    plugin = {
        hyprcapture = {
            helper = "/usr/local/bin/hyprcapture-ui",
        },
    },
})

hl.on("hyprland.start", function()
    hl.exec_cmd("~/.config/hypr/scripts/graphical-session.sh start")
    hl.exec_cmd("kbuildsycoca6 --noincremental")
    hl.exec_cmd("qs -c volume-osd -d -n")
    hl.exec_cmd("~/.config/hypr/scripts/astro-wallpaper.sh apply")
    hl.exec_cmd("~/.config/hypr/scripts/display-switch.sh restore")
    hl.exec_cmd("sh -c 'test -f " .. captureSo .. " && hyprctl plugin load " .. captureSo .. "'")
end)

hl.on("hyprland.shutdown", function()
    hl.exec_cmd("~/.config/hypr/scripts/graphical-session.sh stop")
end)
