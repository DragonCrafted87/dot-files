#!/usr/bin/env bash
# Focus a numbered workspace.
# Visible on any monitor: switch there (cursor follows Hyprland's normal warp).
# Not on a monitor: move it onto the output under the cursor, then focus it.
set -euo pipefail

usage() {
    echo "Usage: switch-workspace.sh <workspace>" >&2
    exit 1
}

case "${1:-}" in
    ""|-h|--help|help) usage ;;
esac

WS="$1"

read -r ACTION TARGET_MON < <(
    hyprctl monitors -j | python3 -c '
import json, subprocess, sys

ws = sys.argv[1]
monitors = json.load(sys.stdin)
if not isinstance(monitors, list):
    monitors = []

def same_ws(active):
    if not isinstance(active, dict):
        return False
    return str(active.get("id", "")) == ws or str(active.get("name", "")) == ws

visible = any(same_ws(m.get("activeWorkspace")) for m in monitors if isinstance(m, dict))
if visible:
    print("focus -")
    raise SystemExit(0)

cursor_mon = ""
try:
    raw = subprocess.check_output(["hyprctl", "cursorpos"], text=True).strip()
    x_s, y_s = raw.split(",", 1)
    cx, cy = int(x_s.strip()), int(y_s.strip())
    for m in monitors:
        if not isinstance(m, dict) or m.get("disabled"):
            continue
        mx, my = int(m.get("x", 0)), int(m.get("y", 0))
        mw, mh = int(m.get("width", 0)), int(m.get("height", 0))
        if mx <= cx < mx + mw and my <= cy < my + mh:
            cursor_mon = str(m.get("name") or "")
            break
except Exception:
    cursor_mon = ""

if not cursor_mon:
    for m in monitors:
        if isinstance(m, dict) and m.get("focused"):
            cursor_mon = str(m.get("name") or "")
            break

print("move " + (cursor_mon or "current"))
' "$WS"
)

if [[ "$ACTION" == "focus" ]]; then
    exec hyprctl dispatch workspace "$WS"
fi

hyprctl --batch "\
dispatch moveworkspacetomonitor $WS $TARGET_MON; \
dispatch workspace $WS"
