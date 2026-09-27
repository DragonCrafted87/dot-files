#!/usr/bin/env bash
# Launch the prefix-isolated Hyprland build. Distro binaries stay first
# on a normal login PATH; this wrapper is only used by the Ly session.
# Do not import LD_LIBRARY_PATH into user systemd; prefix libxkbcommon
# poisons kitty/qs/Brave. hypr-session-exec.sh sets it per hypr* unit.
set -euo pipefail

PREFIX="${HYPRLAND_SOURCE_PREFIX:-/opt/hyprland}"
BIN="${PREFIX}/bin/Hyprland"

if [[ ! -x "$BIN" ]]; then
    printf 'error: missing %s (run setup/modules/desktop/install-hyprland-source.sh)\n' "$BIN" >&2
    exit 1
fi

export PATH="${PREFIX}/bin:${PATH:-/usr/bin}"
export LD_LIBRARY_PATH="${PREFIX}/lib64:${PREFIX}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
export XDG_DATA_DIRS="${PREFIX}/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export XKB_CONFIG_ROOT="${XKB_CONFIG_ROOT:-/usr/share/X11/xkb}"
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-Hyprland}"
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"
export XDG_SESSION_DESKTOP="${XDG_SESSION_DESKTOP:-Hyprland}"

exec "$BIN" "$@"
