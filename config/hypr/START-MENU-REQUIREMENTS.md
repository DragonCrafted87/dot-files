# Start menu requirements

Normative rules for the hyprdesk start menu. The volume overlay is
[`VOLUME-OSD-REQUIREMENTS.md`](VOLUME-OSD-REQUIREMENTS.md). `DESK_SHELL`
in `conf.d/shell.conf` chooses the shell. The git value stays
`quickshell`.

Keywords follow RFC 2119: MUST, MUST NOT, SHOULD, MAY.

## Scope

Super+Space runs `scripts/desk-shell.sh toggle`. When `DESK_SHELL` is
`hyprtoolkit`, that toggle talks to hyprdesk. The menu layer namespace
is `hyprdesk`. The app flyout is `hyprdesk-flyout`. A tray popup is
`hyprdesk-menu`.

## Open and close

1. The menu MUST open at the pointer on the focused monitor, and it MUST
   stay inside that monitor.
1. The menu width MUST be `max(380, min(460, round(monitor width * 0.22)))`.
1. Escape, a click on the empty area outside the menu, and another toggle
   MUST close the menu.
1. The menu MUST take keyboard input on demand. It MUST NOT take an
   exclusive grab, so Super+Space still reaches Hyprland.
1. Opening the menu MUST focus the search field and MUST open the All
   apps flyout.

## Categories and search

1. The categories MUST be All, Accessories, Development, Games, Graphics,
   Internet, Multimedia, Office, Settings, and System.
1. Hovering a category MUST open its flyout without a click. Hover MUST
   NOT change a pinned category.
1. A click MUST pin that category. A second click on the pinned category
   MUST unpin it and close the flyout.
1. Typing in the search field MUST list matches from every category and
   MUST title the flyout Search.
1. The flyout MUST show each matching app by name. An empty result MUST
   say that no apps match.
1. A left click on an app MUST focus a window that is already open for
   that app, on the workspace that was current when the menu opened.
   Otherwise it MUST launch the app there.
1. The flyout MUST scroll when the list is taller than the monitor allows.

## Windows

1. The menu MUST list client windows from `hyprctl clients`.
1. The menu MUST open on minimized windows. When none are minimized, the
   list MUST show every window instead.
1. Min and All MUST switch that filter. Refresh MUST reread the clients.
1. A left click MUST restore that window onto the workspace that was
   current when the menu opened, then close the menu.
1. A right click MUST close that window.
1. An empty list MUST say so. A long title MUST ellipsize instead of
   stretching the menu.

## Tray

1. hyprdesk MUST own `org.kde.StatusNotifierWatcher` while it runs.
1. A left click MUST activate the item. A middle click MUST send the
   secondary action. A vertical scroll MUST scroll the item.
1. A right click MUST open that item's menu at the pointer. The popup
   MUST be only as large as its entries, and it MUST stay on the monitor
   under the pointer.
1. A submenu MUST replace the popup contents and MUST offer Back.
1. When the item has no menu layout, hyprdesk MAY fall back to the item's
   own context menu at the pointer.

## Volume row

1. The row MUST show a mute control, a slider, and the percent.
1. The slider MUST run from 0 to 150% in 2.5% steps. Dragging or
   scrolling it MUST set the default sink and MUST clear mute.
1. The percent MUST use the same text as the volume overlay, including
   `72.5%`.
1. The mute control MUST toggle mute. Muted MUST read MUTE on the control
   and `0%` on the percent.
1. Above 100% the percent MUST use the overdrive red.
1. Moving this slider MUST NOT show the volume overlay.

## Clock and power

1. The menu MUST show CPU, memory, GPU, and network, then the clock and
   the date. The date MUST sit fully above the power row.
1. The power row MUST show lock, logout, suspend, reboot, and shutdown,
   each wide enough to read, in that order.
1. Each power button MUST run `scripts/session-control.sh` with that
   action, then close the menu.

## Appearance

1. Colors, rounding, and fonts MUST come from `hyprtoolkit.conf`.
1. The menu and the flyout MUST match the blur rules for `^hyprdesk$`
   and `^hyprdesk-flyout$`. The dismiss layer MUST NOT be blurred.
