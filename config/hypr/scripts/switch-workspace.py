# pylint: disable=invalid-name
"""Focus a workspace, or move a hidden one onto a monitor.

Numbered workspaces follow the cursor. code-1 through code-5 prefer the
monitor that contains the middle of the layout, and otherwise the widest.
"""

import json
import subprocess
import sys

CODE_WORKSPACES = tuple(f"code-{index}" for index in range(1, 6))
CODE_CLASSES = frozenset(
    {
        "com.microsoft.VSCode",
        "code",
        "Code",
        "code-url-handler",
        "code-oss",
        "codium",
        "VSCodium",
    }
)


def usage():
    print(
        "Usage: switch-workspace.py <workspace> [--prefer] [--send [address]]\n"
        "       switch-workspace.py --place-code <address>",
        file=sys.stderr,
    )
    raise SystemExit(1)


def hyprctl(*args):
    return subprocess.check_output(["hyprctl", *args], text=True)


def hyprctl_json(*args):
    return json.loads(hyprctl(*args, "-j"))


class _Hypr:
    lua: bool | None = None


def hyprctl_is_lua() -> bool:
    if _Hypr.lua is None:
        result = subprocess.run(
            ["hyprctl", "keyword", "misc:disable_xdg_env_checks", "true"],
            capture_output=True,
            text=True,
            check=False,
        )
        _Hypr.lua = "Use eval" in f"{result.stdout}{result.stderr}"
    return bool(_Hypr.lua)


def lua_quote(value: str) -> str:
    return json.dumps(str(value))


def dispatch(lua_expr: str, *legacy: str) -> None:
    if hyprctl_is_lua():
        subprocess.check_call(["hyprctl", "dispatch", lua_expr])
        return
    subprocess.check_call(["hyprctl", "dispatch", *legacy])


def bare_workspace(workspace) -> str:
    text = str(workspace)
    if text.startswith("name:"):
        return text[5:]
    return text


def workspace_selector(workspace) -> str:
    bare = bare_workspace(workspace)
    if bare.isdigit():
        return bare
    return f"name:{bare}"


def same_workspace(active, workspace):
    if not isinstance(active, dict):
        return False
    bare = bare_workspace(workspace)
    return str(active.get("id", "")) == bare or str(active.get("name", "")) == bare


def normalize_address(value) -> str:
    text = str(value or "").strip().lower()
    if text.startswith("address:"):
        text = text.split(":", 1)[1]
    if text.startswith("0x"):
        try:
            return f"0x{int(text, 16):x}"
        except ValueError:
            return text
    return text


def enabled_monitors(monitors):
    enabled = []
    for monitor in monitors:
        if not isinstance(monitor, dict) or monitor.get("disabled"):
            continue
        if int(monitor.get("width") or 0) <= 0 or not monitor.get("name"):
            continue
        enabled.append(monitor)
    return enabled


def preferred_monitor(monitors):
    """Center monitor, otherwise the widest enabled output."""
    enabled = enabled_monitors(monitors)
    if not enabled:
        return None
    left = min(int(monitor["x"]) for monitor in enabled)
    right = max(int(monitor["x"]) + int(monitor["width"]) for monitor in enabled)
    center = (left + right) / 2

    def contains(monitor):
        start = int(monitor["x"])
        return start < center < start + int(monitor["width"])

    containing = [monitor for monitor in enabled if contains(monitor)]
    if len(containing) == 1:
        return str(containing[0]["name"])
    pool = containing or enabled

    def rank(monitor):
        width = int(monitor["width"])
        midpoint = int(monitor["x"]) + width / 2
        return (-width, abs(midpoint - center), int(monitor["x"]), str(monitor["name"]))

    return str(sorted(pool, key=rank)[0]["name"])


def monitor_showing(monitors, workspace):
    for monitor in enabled_monitors(monitors):
        if same_workspace(monitor.get("activeWorkspace"), workspace):
            return str(monitor["name"])
    return None


def workspace_exists(workspaces, workspace) -> bool:
    bare = bare_workspace(workspace)
    for item in workspaces:
        if not isinstance(item, dict):
            continue
        if str(item.get("name", "")) == bare or str(item.get("id", "")) == bare:
            return True
    return False


def client_workspace(client) -> str:
    workspace = client.get("workspace") if isinstance(client, dict) else None
    if not isinstance(workspace, dict):
        return ""
    if workspace.get("name") not in (None, ""):
        return str(workspace["name"])
    return str(workspace.get("id", ""))


def is_code_client(client) -> bool:
    if (
        not isinstance(client, dict)
        or client.get("floating")
        or client.get("mapped") is False
    ):
        return False
    window_class = str(client.get("class") or client.get("initialClass") or "")
    return window_class in CODE_CLASSES


def find_client(clients, address):
    want = normalize_address(address)
    for client in clients:
        if (
            isinstance(client, dict)
            and normalize_address(client.get("address")) == want
        ):
            return client
    return None


def pick_code_workspace(clients, address, names=CODE_WORKSPACES) -> str:
    """First code workspace with no other Code window, else the least occupied."""
    me = find_client(clients, address)
    current = client_workspace(me) if me else ""
    counts = {name: 0 for name in names}
    want = normalize_address(address)
    for client in clients:
        if not isinstance(client, dict):
            continue
        if normalize_address(client.get("address")) == want or not is_code_client(
            client
        ):
            continue
        workspace = client_workspace(client)
        if workspace in counts:
            counts[workspace] += 1
    if current in counts and counts[current] == 0:
        return current
    for name in names:
        if counts[name] == 0:
            return name
    return min(names, key=lambda name: (counts[name], names.index(name)))


def plan_switch(workspace, monitors, options) -> list:
    """Actions that put workspace on a monitor and optionally send one window."""
    bare = bare_workspace(workspace)
    selector = workspace_selector(workspace)
    prefer = bool(options.get("prefer"))
    visible = monitor_showing(monitors, bare)
    if prefer:
        target = preferred_monitor(monitors) or "current"
    else:
        target = options.get("cursor_monitor") or "current"
    window_address = options.get("window_address")
    window_workspace = options.get("window_workspace") or ""
    send_window = bool(window_address) and bare_workspace(window_workspace) != bare

    # workspace.move does not create a named workspace. Focus creates it
    # on the monitor that is current, so aim that monitor first.
    if prefer and visible != target and not options.get("exists", True):
        actions = [("focus_monitor", "", target), ("focus", selector, "")]
        if send_window:
            actions.append(("move_window", selector, normalize_address(window_address)))
            actions.append(("focus", selector, ""))
        return actions

    actions = []
    if prefer:
        if visible != target:
            actions.append(("move_workspace", selector, target))
    elif visible is None:
        actions.append(("move_workspace", selector, target))
    if send_window:
        actions.append(("move_window", selector, normalize_address(window_address)))
    actions.append(("focus", selector, ""))
    return actions


def plan_place_code(clients, monitors, address, workspaces) -> list:
    client = find_client(clients, address)
    if client is None or not is_code_client(client):
        return []
    chosen = pick_code_workspace(clients, address)
    current = client_workspace(client)
    window_address = None
    if bare_workspace(current) != bare_workspace(chosen):
        window_address = normalize_address(address)
    return plan_switch(
        chosen,
        monitors,
        {
            "prefer": True,
            "exists": workspace_exists(workspaces, chosen),
            "cursor_monitor": "current",
            "window_address": window_address,
            "window_workspace": current,
        },
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
            if not isinstance(monitor, dict) or monitor.get("disabled"):
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
        if isinstance(monitor, dict) and monitor.get("focused"):
            name = monitor.get("name")
            if name:
                return str(name)
    return "current"


def parse_args(argv) -> dict:
    args = list(argv[1:])
    if not args or args[0] in {"-h", "--help", "help"}:
        usage()
    if args[0] == "--place-code":
        if len(args) != 2 or not args[1] or args[1].startswith("-"):
            usage()
        return {"place_code": args[1]}
    if args[0].startswith("-"):
        usage()
    parsed = {"workspace": args[0], "prefer": False, "send": None}
    index = 1
    while index < len(args):
        flag = args[index]
        if flag == "--prefer":
            parsed["prefer"] = True
            index += 1
            continue
        if flag == "--send":
            if index + 1 < len(args) and not args[index + 1].startswith("-"):
                parsed["send"] = args[index + 1]
                index += 2
            else:
                parsed["send"] = ""
                index += 1
            continue
        usage()
    return parsed


def monitor_records(payload):
    if not isinstance(payload, list):
        return []
    return [monitor for monitor in payload if isinstance(monitor, dict)]


def client_records(payload):
    if not isinstance(payload, list):
        return []
    return [client for client in payload if isinstance(client, dict)]


def active_window_address() -> str:
    payload = hyprctl_json("activewindow")
    if not isinstance(payload, dict):
        return ""
    return normalize_address(payload.get("address"))


def run_actions(actions) -> None:
    for kind, selector, extra in actions:
        if kind == "focus_monitor":
            lua = "hl.dsp.focus({ monitor = " + lua_quote(extra) + " })"
            dispatch(lua, "focusmonitor", extra)
        elif kind == "move_workspace":
            lua = (
                "hl.dsp.workspace.move({ workspace = "
                + lua_quote(selector)
                + ", monitor = "
                + lua_quote(extra)
                + " })"
            )
            dispatch(lua, "moveworkspacetomonitor", selector, extra)
        elif kind == "move_window":
            window = f"address:{extra}"
            lua = (
                "hl.dsp.window.move({ workspace = "
                + lua_quote(selector)
                + ", follow = false, window = "
                + lua_quote(window)
                + " })"
            )
            dispatch(lua, "movetoworkspacesilent", f"{selector},{window}")
        elif kind == "focus":
            lua = "hl.dsp.focus({ workspace = " + lua_quote(selector) + " })"
            dispatch(lua, "workspace", selector)


def main(argv):
    parsed = parse_args(argv)
    monitors = monitor_records(hyprctl_json("monitors"))
    workspaces = monitor_records(hyprctl_json("workspaces"))
    if "place_code" in parsed:
        clients = client_records(hyprctl_json("clients"))
        actions = plan_place_code(clients, monitors, parsed["place_code"], workspaces)
    else:
        options = {
            "prefer": parsed["prefer"],
            "exists": workspace_exists(workspaces, parsed["workspace"]),
            "cursor_monitor": monitor_under_cursor(monitors),
            "window_address": None,
            "window_workspace": "",
        }
        if parsed["send"] is not None:
            address = normalize_address(parsed["send"]) or active_window_address()
            options["window_address"] = address or None
            client = find_client(client_records(hyprctl_json("clients")), address)
            if client is not None:
                options["window_workspace"] = client_workspace(client)
        actions = plan_switch(parsed["workspace"], monitors, options)
    run_actions(actions)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
