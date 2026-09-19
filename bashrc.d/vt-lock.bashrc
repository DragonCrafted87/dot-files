#!/usr/bin/env bash
# Start a per-tty idle locker on real VTs. SSH is ignored by the script.

if [[ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ]]; then
    return 0 2>/dev/null || true
fi

case "$(tty 2>/dev/null || true)" in
    /dev/tty[0-9]*) ;;
    *) return 0 2>/dev/null || true ;;
esac

_vt_lock="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/vt-idle-lock.sh"
if [[ -x "$_vt_lock" ]]; then
    nohup "$_vt_lock" >/dev/null 2>&1 &
fi
unset _vt_lock
