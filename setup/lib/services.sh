# shellcheck shell=bash
# Sourced by setup/lib/lib.sh. Not an entry point.

enable_service() {
    local unit="$1"
    if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
        return 0
    fi
    log "enable ${unit}"
    run sudo systemctl enable "$unit"
}

enable_user_service() {
    local unit="$1"
    if systemctl --user is-enabled --quiet "$unit" 2>/dev/null; then
        return 0
    fi
    if ! systemctl --user list-unit-files "$unit" >/dev/null 2>&1; then
        warn "user unit ${unit} is not installed yet"
        return 0
    fi
    log "enable --user ${unit}"
    run systemctl --user enable "$unit"
}

disable_user_service() {
    local unit="$1"
    if ! systemctl --user list-unit-files "$unit" >/dev/null 2>&1; then
        return 0
    fi
    if systemctl --user is-enabled --quiet "$unit" 2>/dev/null; then
        log "disable --user ${unit}"
        run systemctl --user disable "$unit"
    fi
}

# Copy a user unit from setup/files into ~/.config/systemd/user.
install_user_unit() {
    local src="$1"
    local dest
    [[ -f "$src" ]] || die "missing ${src}"
    dest="${DOTFILES_HOME}/.config/systemd/user/$(basename "$src")"
    ensure_dir "$(dirname "$dest")"
    if [[ ! -f "$dest" ]] || ! cmp -s "$src" "$dest"; then
        log "user unit ${dest}"
        run install -m 0644 "$src" "$dest"
    fi
}

# Copy a user drop-in from setup/files into ~/.config/systemd/user/<unit>.d/.
install_user_dropin() {
    local unit="$1"
    local src="$2"
    local dest
    [[ -f "$src" ]] || die "missing ${src}"
    dest="${DOTFILES_HOME}/.config/systemd/user/${unit}.d/$(basename "$src")"
    ensure_dir "$(dirname "$dest")"
    if [[ ! -f "$dest" ]] || ! cmp -s "$src" "$dest"; then
        log "user drop-in ${dest}"
        run install -m 0644 "$src" "$dest"
    fi
}

disable_service() {
    local unit="$1"
    if ! systemctl list-unit-files "$unit" >/dev/null 2>&1; then
        return 0
    fi
    if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
        log "disable ${unit}"
        run sudo systemctl disable "$unit"
    fi
    if systemctl is-active --quiet "$unit" 2>/dev/null; then
        log "stop ${unit}"
        run sudo systemctl stop "$unit"
    fi
}

ensure_timezone() {
    local tz="$1"
    local current
    current="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
    if [[ "$current" == "$tz" ]]; then
        return 0
    fi
    log "timezone ${tz}"
    run sudo timedatectl set-timezone "$tz"
}

ensure_hostname() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        return 0
    fi
    local current
    current="$(hostnamectl --static 2>/dev/null || hostname)"
    if [[ "$current" == "$name" ]]; then
        return 0
    fi
    log "hostname ${name}"
    run sudo hostnamectl set-hostname "$name"
}

ensure_systemd_dropin() {
    local unit="$1"
    local name="$2"
    local contents="$3"
    local dest="/etc/systemd/system/${unit}.d/${name}.conf"
    local current=""

    if [[ -f "$dest" ]]; then
        current="$(cat "$dest")"
        if [[ "$current" == "$contents" ]]; then
            return 0
        fi
    fi
    log "systemd drop-in ${dest}"
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        return 0
    fi
    sudo mkdir -p "$(dirname "$dest")"
    printf '%s\n' "$contents" | sudo tee "$dest" >/dev/null
    run sudo systemctl daemon-reload
}
