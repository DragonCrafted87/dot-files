#!/usr/bin/env bash
# Install hyprpaper and the daily astronomy wallpaper timer.
# One still per enabled monitor. Sources are Wikimedia Commons astronomy
# categories plus NASA APOD when reachable.
set -euo pipefail
# shellcheck disable=SC1091
. "${REPO_ROOT:-$DOTFILES_ROOT}/setup/lib/lib.sh"

require_user

paper_pkg="$(pick_pkg hyprpaper || true)"
if [[ -n "$paper_pkg" ]]; then
    ensure_packages "$paper_pkg"
else
    warn "hyprpaper package not found in dnf"
fi

unit_dir="${DOTFILES_HOME}/.config/systemd/user"
ensure_dir "$unit_dir"

for unit in hyprpaper.service astro-wallpaper.service astro-wallpaper.timer; do
    src="${SETUP_FILES_DIR}/wallpaper/${unit}"
    dest="${unit_dir}/${unit}"
    if [[ ! -f "$src" ]]; then
        warn "missing ${src}"
        continue
    fi
    if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
        :
    else
        log "user unit ${dest}"
        run install -m 0644 "$src" "$dest"
    fi
done

run systemctl --user daemon-reload || true
enable_user_service hyprpaper.service
enable_user_service astro-wallpaper.timer

# Bring the daemon back on a machine that is already in a graphical session.
# The oneshot refresh unit must not be the process that owns hyprpaper.
paper_conf="${XDG_STATE_HOME:-${DOTFILES_HOME}/.local/state}/hypr/hyprpaper.conf"
if systemctl --user is-active --quiet graphical-session.target \
    && [[ -f "$paper_conf" ]]; then
    run systemctl --user restart hyprpaper.service
fi
