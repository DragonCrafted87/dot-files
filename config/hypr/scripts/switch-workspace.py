# pylint: disable=invalid-name
"""Focus a workspace, or move a hidden one onto the cursor monitor."""

import json
import subprocess
import sys


def usage():
    print("Usage: switch-workspace.py <workspace>", file=sys.stderr)
    raise SystemExit(1)


def hyprctl(*args):
    return subprocess.check_output(["hyprctl", *args], text=True)


def hyprctl_json(*args):
    return json.loads(hyprctl(*args, "-j"))


def same_workspace(active, workspace):
    if not isinstance(active, dict):
        return False
    return (
        str(active.get("id", "")) == workspace
        or str(active.get("name", "")) == workspace
    )


def workspace_is_visible(monitors, workspace):
    return any(
        same_workspace(monitor.get("activeWorkspace"), workspace)
        for monitor in monitors
    )


def cursor_position():
    try:
        raw = hyprctl("cursorpos").strip()
        x_text, y_text = raw.split(",", 1)
        return int(x_text.strip()), int(y_text.strip())
    except (OSError, ValueError, subprocess.CalledProcessError):
        return None


def monitor_under_cursor(monitors):
    position = cursor_position()
    if position is not None:
        cursor_x, cursor_y = position
        for monitor in monitors:
            if monitor.get("disabled"):
                continue
            left = int(monitor.get("x", 0))
            top = int(monitor.get("y", 0))
            width = int(monitor.get("width", 0))
            height = int(monitor.get("height", 0))
            if left <= cursor_x < left + width and top <= cursor_y < top + height:
                name = monitor.get("name")
                if name:
                    return str(name)
    for monitor in monitors:
        if monitor.get("focused"):
            name = monitor.get("name")
            if name:
                return str(name)
    return "current"


def main(argv):
    if len(argv) != 2 or argv[1] in {"-h", "--help", "help"}:
        usage()
    workspace = argv[1]
    monitors = hyprctl_json("monitors")
    if not isinstance(monitors, list):
        monitors = []
    monitors = [monitor for monitor in monitors if isinstance(monitor, dict)]
    if workspace_is_visible(monitors, workspace):
        subprocess.check_call(["hyprctl", "dispatch", "workspace", workspace])
        return 0
    target = monitor_under_cursor(monitors)
    subprocess.check_call(
        [
            "hyprctl",
            "--batch",
            f"dispatch moveworkspacetomonitor {workspace} {target}; dispatch workspace {workspace}",
        ]
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
