# Palette leftovers

Tracked after the Tango Dark pass. Not scheduled.

## Cursors

- Hypr / GTK / KDE already name `breeze_cursors`.
- Still want a Tango-shaped pointer set if one exists that is HiDPI-clean
  and packaged, or a small custom theme under `~/.icons`.
- Decide whether Hyprcursor (`.hlc`) is worth shipping vs XCursor only.

## local builds

- current version of hyprland

## network

- lowercase the rclone OneDrive mount. Local dir is still
  `~/network/Dragon-OneDrive` (`RCLONE_SHARE=Dragon-OneDrive` in
  `setup/files/network/mount-network.sh`). CIFS mountpoints are already
  lowercase.

## session stop

- after the workstation-session.target reboot, one of the xdg units sat
  through the full 90s stop timeout. Likely `xdg-desktop-portal` or
  `xdg-document-portal`. Journal which unit, then shorten TimeoutStopSec
  or find what it was waiting on.
