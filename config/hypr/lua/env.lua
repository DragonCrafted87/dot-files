-- Mirrors conf.d/env.conf for Hyprland 0.56+.

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("XCURSOR_THEME", "breeze_cursors")
hl.env("HYPRCURSOR_THEME", "breeze_cursors")

hl.env("XDG_DATA_HOME", "/home/dragon/.local/share")
hl.env("XDG_CONFIG_HOME", "/home/dragon/.config")
hl.env("XDG_STATE_HOME", "/home/dragon/.local/state")
hl.env("XDG_CACHE_HOME", "/home/dragon/.cache")

hl.env("XDG_CURRENT_DESKTOP", "Hyprland:KDE")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("QT_QPA_PLATFORMTHEME", "kde")
hl.env("QT_QUICK_CONTROLS_STYLE", "org.kde.desktop")
hl.env("GDK_BACKEND", "wayland,x11")
hl.env("GTK_THEME", "Adwaita:dark")
hl.env("TERMINAL", "kitty")

hl.env("SAL_USE_VCLPLUGIN", "kf6")
hl.env("SSH_ASKPASS_REQUIRE", "never")
