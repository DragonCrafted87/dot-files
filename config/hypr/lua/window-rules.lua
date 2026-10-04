hl.config({
    xwayland = {
        enabled = true,
    },
})

hl.window_rule({
    name = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name = "fix-xwayland-drags",
    match = {
        class = "^$",
        title = "^$",
        xwayland = true,
        float = true,
        fullscreen = false,
        pin = false,
    },
    no_focus = true,
})

hl.window_rule({
    name = "guild-wars-span",
    match = { class = "^Gw\\.exe$" },
    float = true,
    size = "8560 1440",
    move = "0 0",
    pin = true,
    no_anim = true,
    no_blur = true,
    border_size = 0,
    no_shadow = true,
    rounding = 0,
    suppress_event = "maximize fullscreen",
})

-- One tiled Code window per code-1..code-5. The script also chooses the monitor.
-- hl.on callbacks die after 50ms, and os.execute blocks the compositor
-- thread, so hyprctl cannot answer until the callback returns. Spawn and
-- return. Class often arrives after the window is mapped.
local code_classes = {
    ["com.microsoft.VSCode"] = true,
    ["code"] = true,
    ["Code"] = true,
    ["code-url-handler"] = true,
    ["code-oss"] = true,
    ["codium"] = true,
    ["VSCodium"] = true,
}

local function shell_quote(text)
    return "'" .. tostring(text):gsub("'", "'\\''") .. "'"
end

local function place_code_window(window)
    if window == nil or window.floating then
        return
    end
    if not (code_classes[window.class] or code_classes[window.initial_class]) then
        return
    end
    if window.address == nil or window.address == "" then
        return
    end
    hl.exec_cmd(
        "python3 "
            .. (os.getenv("HOME") or "")
            .. "/.config/hypr/scripts/switch-workspace.py --place-code "
            .. shell_quote(window.address)
    )
end

hl.on("window.open", place_code_window)
hl.on("window.class", place_code_window)
