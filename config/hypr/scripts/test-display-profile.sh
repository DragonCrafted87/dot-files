#!/usr/bin/env bash
# Saved workspace keys. Hyprland treats a leading "-" as an offset from
# the focused workspace and clamps it at 1, so an id of -1337 moves
# workspace 1. The map stores the name, and restore never dispatches
# the raw id.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/hyprctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${HYPRCTL_LOG:?}"
case "${1:-}" in
    workspaces) cat "${HYPRCTL_WORKSPACES:?}" ;;
    monitors) cat "${HYPRCTL_MONITORS:?}" ;;
esac
exit 0
EOF
chmod +x "$tmp/hyprctl"

export PATH="$tmp:${PATH}"
export HYPRCTL_LOG="$tmp/log"
export HYPRCTL_WORKSPACES="$tmp/workspaces.json"
export HYPRCTL_MONITORS="$tmp/monitors.json"
: >"$HYPRCTL_LOG"

# shellcheck disable=SC1091
source "${script_dir}/display-profile.sh"
trap 'rm -rf "$tmp"' EXIT
HYPRCTL_LUA=1
SAVED_WS_FILE="$tmp/saved"

fail() {
    printf 'fail: %s\n' "$*" >&2
    exit 1
}

write_state() {
    local workspaces="$1" monitors="$2"
    printf '%s\n' "$workspaces" >"$HYPRCTL_WORKSPACES"
    printf '%s\n' "$monitors" >"$HYPRCTL_MONITORS"
    : >"$HYPRCTL_LOG"
}

desk_monitors() {
    cat <<'EOF'
[
  {"name": "DP-2", "disabled": false, "width": 2560, "height": 1440,
   "activeWorkspace": {"id": 1, "name": "1"}},
  {"name": "DP-3", "disabled": false, "width": 3440, "height": 1440,
   "activeWorkspace": {"id": -1337, "name": "code-1"}},
  {"name": "HDMI-A-1", "disabled": false, "width": 2560, "height": 1440,
   "activeWorkspace": {"id": 3, "name": "3"}}
]
EOF
}

desk_workspaces() {
    cat <<'EOF'
[
  {"id": 1, "name": "1", "monitor": "DP-2"},
  {"id": 3, "name": "3", "monitor": "HDMI-A-1"},
  {"id": -1337, "name": "code-1", "monitor": "DP-3"},
  {"id": -1338, "name": "code-2", "monitor": "DP-3"},
  {"id": -9, "name": "", "monitor": "DP-3"},
  {"id": -5, "name": "special:scratch", "monitor": "DP-2"}
]
EOF
}

assert_dump_uses_names() {
    local dump
    write_state "$(desk_workspaces)" "$(desk_monitors)"
    dump="$(workspace_map_dump)"
    printf '%s\n' "$dump" | grep -qx 'workspace=code-1:DP-3' || fail "dump missed code-1"
    printf '%s\n' "$dump" | grep -qx 'workspace=code-2:DP-3' || fail "dump missed code-2"
    printf '%s\n' "$dump" | grep -qx 'workspace=1:DP-2' || fail "dump missed workspace 1"
    printf '%s\n' "$dump" | grep -qx 'workspace=special:scratch:DP-2' || fail "dump missed special"
    printf '%s\n' "$dump" | grep -qx 'active=DP-3:code-1' || fail "active line used an id"
    if printf '%s\n' "$dump" | grep -q 'workspace=-'; then
        fail "dump stored a negative id"
    fi
}

assert_selectors() {
    local sel
    write_state "$(desk_workspaces)" "$(desk_monitors)"
    sel="$(workspace_selector '1')"
    [[ "$sel" == "1" ]] || fail "numeric selector was ${sel}"
    sel="$(workspace_selector 'code-1')"
    [[ "$sel" == "name:code-1" ]] || fail "name selector was ${sel}"
    sel="$(workspace_selector '-1337')"
    [[ "$sel" == "name:code-1" ]] || fail "legacy id selector was ${sel}"
    sel="$(workspace_selector 'special:scratch')"
    [[ "$sel" == "special:scratch" ]] || fail "special selector was ${sel}"
    if workspace_selector '-9999'; then
        fail "a missing id produced a selector"
    fi
}

assert_already_placed_is_quiet() {
    write_state "$(desk_workspaces)" "$(desk_monitors)"
    cat >"$SAVED_WS_FILE" <<'EOF'
workspace=1:DP-2
workspace=3:HDMI-A-1
workspace=code-1:DP-3
workspace=-1337:DP-3
workspace=-9999:DP-3
active=DP-2:1
active=DP-3:code-1
active=HDMI-A-1:3
EOF
    restore_saved_workspaces_now || fail "quiet restore failed"
    [[ ! -f "$SAVED_WS_FILE" ]] || fail "quiet restore left the map"
    if grep -q '^dispatch ' "$HYPRCTL_LOG"; then
        fail "quiet restore dispatched: $(grep '^dispatch ' "$HYPRCTL_LOG")"
    fi
}

assert_move_uses_name() {
    local moves
    write_state "$(desk_workspaces)" "$(desk_monitors)"
    python3 - "$HYPRCTL_WORKSPACES" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)
for workspace in data:
    if workspace.get("name") == "code-1":
        workspace["monitor"] = "HDMI-A-1"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle)
PY
    cat >"$SAVED_WS_FILE" <<'EOF'
workspace=-1337:DP-3
active=DP-3:code-2
EOF
    if restore_saved_workspaces_now; then
        fail "mismatched map reported success"
    fi
    [[ -f "$SAVED_WS_FILE" ]] || fail "failed restore deleted the map"
    moves="$(grep -c 'hl.dsp.workspace.move' "$HYPRCTL_LOG" || true)"
    [[ "$moves" == "1" ]] || fail "expected one move, got ${moves}"
    grep -q 'name:code-1' "$HYPRCTL_LOG" || fail "move did not use name:code-1"
    if grep -q -- '-1337' "$HYPRCTL_LOG"; then
        fail "dispatch still contained -1337"
    fi
    grep -q 'hl.dsp.focus' "$HYPRCTL_LOG" || fail "expected a focus when the active workspace differed"
}

assert_missing_map_is_success() {
    rm -f "$SAVED_WS_FILE"
    restore_saved_workspaces_now || fail "missing map should succeed"
}

assert_gone_active_is_skipped() {
    write_state "$(desk_workspaces)" "$(desk_monitors)"
    cat >"$SAVED_WS_FILE" <<'EOF'
workspace=1:DP-2
active=DP-3:-9999
EOF
    restore_saved_workspaces_now || fail "gone active id should not fail the map"
    [[ ! -f "$SAVED_WS_FILE" ]] || fail "gone active id left the map"
    if grep -q '^dispatch ' "$HYPRCTL_LOG"; then
        fail "gone active id dispatched"
    fi
}

assert_offline_monitor_does_not_dispatch() {
    write_state "$(desk_workspaces)" "$(desk_monitors)"
    python3 - "$HYPRCTL_WORKSPACES" "$HYPRCTL_MONITORS" <<'PY'
import json
import sys

workspaces, monitors = sys.argv[1:]
with open(workspaces, encoding="utf-8") as handle:
    data = json.load(handle)
for workspace in data:
    if workspace.get("id") == 3:
        workspace["monitor"] = "DP-2"
with open(workspaces, "w", encoding="utf-8") as handle:
    json.dump(data, handle)
with open(monitors, encoding="utf-8") as handle:
    data = json.load(handle)
for monitor in data:
    if monitor.get("name") == "HDMI-A-1":
        monitor["disabled"] = True
        monitor["width"] = 0
with open(monitors, "w", encoding="utf-8") as handle:
    json.dump(data, handle)
PY
    cat >"$SAVED_WS_FILE" <<'EOF'
workspace=3:HDMI-A-1
EOF
    if restore_saved_workspaces_now; then
        fail "offline monitor reported success"
    fi
    [[ -f "$SAVED_WS_FILE" ]] || fail "offline monitor deleted the map"
    if grep -q '^dispatch ' "$HYPRCTL_LOG"; then
        fail "offline monitor dispatched"
    fi
}

assert_dump_uses_names
assert_selectors
assert_already_placed_is_quiet
assert_move_uses_name
assert_missing_map_is_success
assert_gone_active_is_skipped
assert_offline_monitor_does_not_dispatch
printf 'ok\n'
