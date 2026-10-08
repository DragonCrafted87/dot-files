-- Session start and shutdown. Monitor restore is display-switch.sh.

local captureSo = "/usr/local/lib/libhyprcapture.so"

local function desk_shell()
    local path = (os.getenv("HOME") or "") .. "/.config/hypr/conf.d/shell.conf"
    local handle = io.open(path, "r")
    if handle == nil then
        return "quickshell"
    end
    local value = "quickshell"
    for line in handle:lines() do
        local found = line:match("^DESK_SHELL%s*=%s*(%w+)")
        if found == "hyprtoolkit" or found == "quickshell" then
            value = found
        end
    end
    handle:close()
    return value
end

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
    if desk_shell() == "hyprtoolkit" then
        hl.exec_cmd("systemctl --user stop qs-startmenu.service")
        hl.exec_cmd("systemctl --user start hyprlauncher.service")
    else
        hl.exec_cmd("qs -c volume-osd -d -n")
    end
    hl.exec_cmd("~/.config/hypr/scripts/astro-wallpaper.sh apply")
    hl.exec_cmd("~/.config/hypr/scripts/display-switch.sh restore")
    hl.exec_cmd("sh -c 'test -f " .. captureSo .. " && hyprctl plugin load " .. captureSo .. "'")
end)

hl.on("hyprland.shutdown", function()
    hl.exec_cmd("~/.config/hypr/scripts/graphical-session.sh stop")
end)
