# Palette leftovers

Tracked after the Tango Dark pass. Not scheduled.

## Cursors

- Hypr / GTK / KDE already name `breeze_cursors`.
- Still want a Tango-shaped pointer set if one exists that is HiDPI-clean
  and packaged, or a small custom theme under `~/.icons`.
- Decide whether Hyprcursor (`.hlc`) is worth shipping vs XCursor only.

## local builds

- current version of hyprland

## BOINC

- After every machine has the native `/usr/local` client, drop leftover
  Flatpak references: `edu.berkeley.BOINC`, the
  `~/.var/app/edu.berkeley.BOINC` migration in `install-boinc.sh`, and
  any docs that still mention the Flathub app. Keep the uninstall step
  until that sweep so a late box still gets cleaned up.
