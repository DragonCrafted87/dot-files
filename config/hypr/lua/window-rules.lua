-- Mirrors conf.d/window-rules.conf for Hyprland 0.56+.

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
