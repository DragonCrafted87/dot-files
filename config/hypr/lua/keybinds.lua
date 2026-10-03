-- Mirrors conf.d/keybinds.conf for Hyprland 0.56+.

local mainMod = "SUPER"
local terminal = "kitty"
local fileManager = "dolphin"
local scripts = os.getenv("HOME") .. "/.config/hypr/scripts"

hl.bind(mainMod .. " + Space", hl.dsp.exec_cmd("qs -c startmenu ipc call startmenu toggle"))
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + C", hl.dsp.window.close())
hl.bind(mainMod .. " + F4", hl.dsp.exec_cmd(scripts .. "/session-control.sh logout"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("loginctl lock-session"))

hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }))

for i = 1, 10 do
    local key = i % 10
    hl.bind(
        mainMod .. " + " .. key,
        hl.dsp.exec_cmd("python3 " .. scripts .. "/switch-workspace.py " .. i)
    )
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- code-1..code-5. D is not a modifier, so the digit is a submap.
-- Uppercase letters in a Lua bind string already mean Shift, so the
-- send chord spells d in lowercase.
local switch_code = "python3 " .. scripts .. "/switch-workspace.py"

local function code_submap(name, extra)
    hl.define_submap(name, "reset", function()
        for i = 1, 5 do
            local command = switch_code .. " code-" .. i .. " --prefer" .. extra
            -- The digit is pressed while Super, and often Shift, are still held.
            local keys = {
                tostring(i),
                "SUPER + " .. i,
                "SHIFT + " .. i,
                "SUPER + SHIFT + " .. i,
            }
            for _, key in ipairs(keys) do
                hl.bind(key, hl.dsp.exec_cmd(command), { ignore_mods = true })
            end
        end
        hl.bind("escape", hl.dsp.submap("reset"), { ignore_mods = true })
        hl.bind("catchall", hl.dsp.submap("reset"), { ignore_mods = true })
    end)
end

hl.bind(mainMod .. " + D", hl.dsp.submap("code-ws"))
code_submap("code-ws", "")
hl.bind(mainMod .. " + SHIFT + d", hl.dsp.submap("code-send"))
code_submap("code-send", " --send")

hl.bind(mainMod .. " + S", hl.dsp.window.move({ workspace = "special:minimized" }))

hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

hl.bind(
    "XF86AudioRaiseVolume",
    hl.dsp.exec_cmd("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 2.5%+"),
    { locked = true, repeating = true }
)
hl.bind(
    "XF86AudioLowerVolume",
    hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2.5%-"),
    { locked = true, repeating = true }
)
hl.bind(
    "XF86AudioMute",
    hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),
    { locked = true, repeating = true }
)
hl.bind(
    "XF86AudioMicMute",
    hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),
    { locked = true, repeating = true }
)
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl s 10%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl s 10%-"), { locked = true, repeating = true })

hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

hl.bind(mainMod .. " + ALT + D", hl.dsp.exec_cmd(scripts .. "/display-switch.sh desk"))
hl.bind(mainMod .. " + ALT + S", hl.dsp.exec_cmd(scripts .. "/display-switch.sh single"))
hl.bind(mainMod .. " + ALT + W", hl.dsp.exec_cmd(scripts .. "/astro-wallpaper.sh refresh"))

-- Uppercase letters in a Lua bind string already mean Shift.
hl.bind(mainMod .. " + SHIFT + s", function()
    if hl.plugin.hyprcapture ~= nil then
        hl.plugin.hyprcapture.open()
    end
end)
hl.bind(mainMod .. " + SHIFT + r", function()
    if hl.plugin.hyprcapture ~= nil then
        hl.plugin.hyprcapture.record_toggle()
    end
end)
