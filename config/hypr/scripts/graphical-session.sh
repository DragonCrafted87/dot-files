#!/usr/bin/env bash
# Import compositor env into the user systemd, then start a bind unit so
# graphical-session.target can become active. ly -> Hyprland.desktop never
# reaches that target on its own (RefuseManualStart=yes).
set -euo pipefail

UNIT=hyprland-session.service
UNIT_DST="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/${UNIT}"
DOTFILES_ROOT_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/dot-files/root"

SET_VARS=()
SESSION_VARS=(
    DISPLAY
    WAYLAND_DISPLAY
    HYPRLAND_INSTANCE_SIGNATURE
    XDG_CURRENT_DESKTOP
    XDG_SESSION_TYPE
    XDG_SESSION_DESKTOP
    XDG_DATA_HOME
    XDG_CONFIG_HOME
    XDG_STATE_HOME
    XDG_CACHE_HOME
    QT_QPA_PLATFORM
    QT_QPA_PLATFORMTHEME
    GDK_BACKEND
)

usage() {
    echo "Usage: graphical-session.sh start|stop|status|help" >&2
}

log() {
    printf 'graphical-session: %s\n' "$*"
}

set_vars() {
    local name
    SET_VARS=()
    for name in "${SESSION_VARS[@]}"; do
        if [[ -n "${!name:-}" ]]; then
            SET_VARS+=("$name")
        fi
    done
}

import_env() {
    set_vars
    if ((${#SET_VARS[@]} == 0)); then
        log "no session variables set to import"
        return 0
    fi
    dbus-update-activation-environment --systemd "${SET_VARS[@]}"
    systemctl --user import-environment "${SET_VARS[@]}"
}

repo_root() {
    if [[ -n "${DOTFILES_ROOT:-}" ]]; then
        printf '%s\n' "$DOTFILES_ROOT"
        return 0
    fi
    if [[ -f "$DOTFILES_ROOT_FILE" ]]; then
        cat "$DOTFILES_ROOT_FILE"
    fi
}

ensure_unit() {
    local src root
    root="$(repo_root)"
    src="${root}/setup/files/hypr/${UNIT}"
    if [[ -n "$root" && -f "$src" ]]; then
        mkdir -p "$(dirname "$UNIT_DST")"
        if [[ ! -f "$UNIT_DST" ]] || ! cmp -s "$src" "$UNIT_DST"; then
            install -m 0644 "$src" "$UNIT_DST"
            systemctl --user daemon-reload
        fi
        return 0
    fi
    if [[ -f "$UNIT_DST" ]]; then
        return 0
    fi
    log "missing ${UNIT}; run update-role or copy setup/files/hypr/${UNIT}"
    return 1
}

cmd_start() {
    import_env
    ensure_unit
    if systemctl --user is-active --quiet "$UNIT"; then
        # Linger can leave the bind up after a crash without exec-shutdown.
        # Restart so WantedBy=graphical-session.target units run again.
        log "restarting ${UNIT} for this compositor"
        systemctl --user restart "$UNIT"
    else
        systemctl --user start "$UNIT"
        log "started ${UNIT}"
    fi
}

cmd_stop() {
    if ! systemctl --user is-active --quiet "$UNIT"; then
        return 0
    fi
    systemctl --user stop "$UNIT"
    log "stopped ${UNIT}"
}

cmd_status() {
    local unit
    for unit in graphical-session.target "$UNIT" network-mounts.service hypridle.service hyprpolkitagent.service mako.service; do
        printf '%s %s\n' "$unit" "$(systemctl --user is-active "$unit" || true)"
    done
}

cmd="${1:-}"
case "$cmd" in
    start) cmd_start ;;
    stop) cmd_stop ;;
    status) cmd_status ;;
    -h | --help | help) usage ;;
    "")
        usage
        exit 1
        ;;
    *)
        usage
        exit 1
        ;;
esac
