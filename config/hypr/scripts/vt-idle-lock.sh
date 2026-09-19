#!/usr/bin/env bash
# Lock a text VT after 2x the Hyprland screen-blank timeout.
# Skip SSH and graphical sessions. One watcher per tty.
set -euo pipefail

BLANK_SECONDS="${VT_BLANK_SECONDS:-420}"
LOCK_SECONDS="${VT_LOCK_SECONDS:-$((BLANK_SECONDS * 2))}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
POLL=15

if [[ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ]]; then
    exit 0
fi

TTY_NAME="$(tty 2>/dev/null || true)"
case "$TTY_NAME" in
    /dev/tty[0-9]*) ;;
    *) exit 0 ;;
esac

# Graphical seat (Hyprland / ly session) is handled by hypridle.
if [[ -n "${WAYLAND_DISPLAY:-}" || -n "${DISPLAY:-}" || -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    exit 0
fi
if [[ "${XDG_SESSION_TYPE:-}" == wayland || "${XDG_SESSION_TYPE:-}" == x11 ]]; then
    exit 0
fi

mkdir -p "$STATE_DIR"
LOCK_FILE="${STATE_DIR}/vt-idle-lock.${TTY_NAME##*/}.pid"
if [[ -f "$LOCK_FILE" ]]; then
    old="$(tr -d '[:space:]' <"$LOCK_FILE" || true)"
    if [[ -n "$old" ]] && kill -0 "$old" 2>/dev/null; then
        exit 0
    fi
fi
echo $$ >"$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

lock_now() {
    if command -v vlock >/dev/null 2>&1; then
        vlock -n
        return
    fi
    if command -v physlock >/dev/null 2>&1; then
        physlock -s
        return
    fi
    printf 'vt-idle-lock: no vlock/physlock on PATH\n' >&2
}

idle_seconds() {
    local hint session
    session="${XDG_SESSION_ID:-}"
    if [[ -n "$session" ]] && command -v loginctl >/dev/null 2>&1; then
        hint="$(loginctl show-session "$session" -p IdleSinceHint --value 2>/dev/null || true)"
        if [[ -n "$hint" && "$hint" != 0 ]]; then
            # IdleSinceHint is usec since epoch.
            python3 -c "import time,sys; h=int(sys.argv[1]); print(int(time.time()-h/1e6) if h>1e12 else 0)" "$hint" 2>/dev/null || echo 0
            return 0
        fi
    fi
    echo 0
}

while true; do
    sleep "$POLL"
    [[ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ]] && exit 0
    idle="$(idle_seconds)"
    if [[ "${idle:-0}" -ge "$LOCK_SECONDS" ]]; then
        lock_now
        # After unlock, wait so we do not immediately re-lock.
        sleep 2
    fi
done
