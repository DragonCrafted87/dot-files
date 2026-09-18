#!/usr/bin/env bash
# hyprctl talks to a UNIX socket under $XDG_RUNTIME_DIR/hypr/$HIS/.
# Local terminals inherit those vars from the compositor. SSH sessions
# usually do not, so reconstruct them when Hyprland is running here.
#
# hyprlock-restore: run from another TTY after hyprlock dies and the
# session-lock crash overlay is on the graphical VT.
#
# qs-restart: kill and relaunch startmenu + volume-osd.

if is_windows 2>/dev/null; then
    return 0 2>/dev/null || true
fi

_hypr_runtime_dir() {
    if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
        printf '%s\n' "$XDG_RUNTIME_DIR"
        return 0
    fi
    local uid
    uid="$(id -u)"
    if [[ -d "/run/user/${uid}" ]]; then
        printf '%s\n' "/run/user/${uid}"
        return 0
    fi
    return 1
}

_hypr_pick_instance() {
    local hypr_root="$1"
    local newest="" newest_mtime=0 path mtime

    [[ -d "$hypr_root" ]] || return 1

    shopt -s nullglob
    for path in "$hypr_root"/*; do
        [[ -d "$path" ]] || continue
        [[ -S "$path/.socket.sock" ]] || continue
        mtime="$(stat -c '%Y' "$path" 2>/dev/null || printf '0')"
        if (( mtime >= newest_mtime )); then
            newest_mtime="$mtime"
            newest="$path"
        fi
    done
    shopt -u nullglob

    [[ -n "$newest" ]] || return 1
    printf '%s\n' "$(basename "$newest")"
}

_hypr_setup_ssh_env() {
    local runtime hypr_root his

    runtime="$(_hypr_runtime_dir)" || return 0
    if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
        export XDG_RUNTIME_DIR="$runtime"
    fi

    hypr_root="${runtime}/hypr"
    [[ -d "$hypr_root" ]] || return 0

    if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        his="$(_hypr_pick_instance "$hypr_root")" || return 0
        export HYPRLAND_INSTANCE_SIGNATURE="$his"
    fi

    if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
        if [[ -S "${runtime}/wayland-1" ]]; then
            export WAYLAND_DISPLAY=wayland-1
        elif [[ -S "${runtime}/wayland-0" ]]; then
            export WAYLAND_DISPLAY=wayland-0
        fi
    fi
}

steam-wrap() {
    local wrap="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/steam-proton-wrap.sh"
    local cmd="${1:-status}"

    case "$cmd" in
        games | windows | running)
            if ! command -v hyprctl >/dev/null 2>&1; then
                echo "hyprctl not available" >&2
                return 1
            fi
            hyprctl clients -j 2>/dev/null | python3 -c '
import json, sys
try:
    clients = json.load(sys.stdin)
except Exception:
    raise SystemExit(1)
rows = []
for c in clients:
    cls = str(c.get("class") or "")
    title = str(c.get("title") or "")
    if not (cls.startswith("steam_app_") or cls.lower().endswith(".exe") or "proton" in cls.lower() or "gamescope" in cls.lower()):
        continue
    mon = c.get("monitor")
    at = c.get("at") or [0, 0]
    size = c.get("size") or [0, 0]
    print(f"{cls}\tmon={mon}\t{at[0]},{at[1]} {size[0]}x{size[1]}\t{title}")
'
            return "${PIPESTATUS[0]}"
            ;;
        log)
            tail -n "${2:-30}" "${XDG_STATE_HOME:-$HOME/.local/state}/hypr/steam-wrap.log"
            return $?
            ;;
    esac

    if [[ ! -x "$wrap" ]]; then
        echo "missing $wrap" >&2
        return 1
    fi
    if [[ "$#" -eq 0 ]]; then
        "$wrap" status
    else
        "$wrap" "$@"
    fi
}

# Official recovery when hyprlock crashes and Hyprland shows the
# session-lock restore overlay. Switch to another TTY, login, run this,
# then switch back and unlock.
hyprlock-restore() {
    if ! command -v hyprctl >/dev/null 2>&1; then
        printf 'hyprctl not available\n' >&2
        return 1
    fi
    if ! command -v hyprlock >/dev/null 2>&1; then
        printf 'hyprlock not available\n' >&2
        return 1
    fi

    local instance="${1:-0}"

    hyprctl --instance "$instance" 'keyword misc:allow_session_lock_restore 1' || {
        printf 'failed to enable session lock restore on instance %s\n' "$instance" >&2
        return 1
    }
    killall -9 hyprlock 2>/dev/null || true
    hyprctl --instance "$instance" 'dispatch exec hyprlock' || {
        printf 'failed to relaunch hyprlock on instance %s\n' "$instance" >&2
        return 1
    }
    printf 'hyprlock relaunched on instance %s; switch back to the graphical TTY and unlock\n' "$instance"
}

qs-restart() {
    local starter="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/startmenu.sh"

    pkill -f 'qs -c startmenu' >/dev/null 2>&1 || true
    pkill -f 'qs -c volume-osd' >/dev/null 2>&1 || true
    sleep 0.3

    if [[ -x "$starter" ]]; then
        nohup "$starter" >/dev/null 2>&1 &
    else
        nohup qs -c startmenu -d -n >/dev/null 2>&1 &
    fi
    nohup qs -c volume-osd -d -n >/dev/null 2>&1 &
    printf 'restarted qs startmenu and volume-osd\n'
}

_hypr_setup_ssh_env
unset -f _hypr_runtime_dir _hypr_pick_instance _hypr_setup_ssh_env
