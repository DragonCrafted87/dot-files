# shellcheck shell=bash
# Sourced by setup/lib/lib.sh. Not an entry point.

# Modules run in a subprocess, so a restart request has to survive on disk.
request_qs_restart() {
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        log "dry-run: would flag qs restart (${DOTFILES_QS_RESTART_FLAG})"
        return 0
    fi
    printf '1\n' >"$DOTFILES_QS_RESTART_FLAG"
}

# XDG desktop dir, falling back to ~/desktop when xdg-user-dir is missing
# or reports $HOME (its unset default).
resolve_desktop_dir() {
    local desktop_dir="${XDG_DESKTOP_DIR:-}"

    if [[ -z "$desktop_dir" ]] && command -v xdg-user-dir >/dev/null 2>&1; then
        desktop_dir="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
    fi
    if [[ -z "$desktop_dir" || "$desktop_dir" == "$HOME" || "$desktop_dir" == "$DOTFILES_HOME" ]]; then
        desktop_dir="${DOTFILES_HOME}/desktop"
    fi
    printf '%s\n' "$desktop_dir"
}

# Install a .desktop into ~/.local/share/applications and ~/desktop.
# Marks qs for restart when the start menu needs to reread launchers.
install_user_desktop() {
    local src="$1"
    local name
    local desktop_dir
    local apps_dir="${DOTFILES_HOME}/.local/share/applications"
    local changed=0

    name="$(basename "$src")"
    [[ -f "$src" ]] || die "missing ${src}"

    desktop_dir="$(resolve_desktop_dir)"

    ensure_dir "$desktop_dir"
    ensure_dir "$apps_dir"

    if [[ ! -f "${apps_dir}/${name}" ]] || ! cmp -s "$src" "${apps_dir}/${name}"; then
        log "install desktop ${apps_dir}/${name}"
        run install -m 0755 "$src" "${apps_dir}/${name}"
        changed=1
    fi
    if [[ ! -f "${desktop_dir}/${name}" ]] || ! cmp -s "$src" "${desktop_dir}/${name}"; then
        log "install desktop ${desktop_dir}/${name}"
        run install -m 0755 "$src" "${desktop_dir}/${name}"
        changed=1
    fi

    if [[ "$changed" -eq 1 ]]; then
        if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
            if command -v update-desktop-database >/dev/null 2>&1; then
                update-desktop-database "$apps_dir" >/dev/null 2>&1 || true
            fi
            if command -v xdg-desktop-menu >/dev/null 2>&1; then
                xdg-desktop-menu forceupdate >/dev/null 2>&1 || true
            fi
        fi
        request_qs_restart
    fi
}

restart_qs_if_needed() {
    local starter="${CONFIG_TARGET_DIR}/hypr/scripts/startmenu.sh"

    if [[ ! -f "$DOTFILES_QS_RESTART_FLAG" ]]; then
        return 0
    fi

    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        log "dry-run: would restart qs startmenu"
        return 0
    fi

    rm -f "$DOTFILES_QS_RESTART_FLAG"

    if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && ! pgrep -x Hyprland >/dev/null 2>&1; then
        log "skip qs restart: no Hyprland session"
        return 0
    fi

    if systemctl --user is-enabled --quiet qs-startmenu.service 2>/dev/null; then
        log "restart qs startmenu"
        run systemctl --user restart qs-startmenu.service
        return 0
    fi

    if [[ ! -x "$starter" ]]; then
        warn "skip qs restart: missing ${starter}"
        return 0
    fi

    log "restart qs startmenu"
    pkill -f 'qs -c startmenu' >/dev/null 2>&1 || true
    sleep 0.3
    nohup "$starter" >/dev/null 2>&1 &
}
