#!/usr/bin/env bash
# Login and session stack for GUI roles, matching the current workstation.

set -euo pipefail
# shellcheck disable=SC1091
. "${REPO_ROOT:-$DOTFILES_ROOT}/setup/lib/lib.sh"

require_user

ensure_packages \
    ly \
    hyprland \
    hyprland-qtutils \
    hypridle \
    hyprlock \
    hyprpicker \
    hyprpolkitagent \
    hyprcursor \
    quickshell \
    kitty \
    uwsm \
    xdg-desktop-portal \
    xdg-desktop-portal-hyprland \
    xdg-desktop-portal-gtk \
    pipewire \
    pipewire-pulse \
    wireplumber \
    pavucontrol-qt \
    playerctl \
    brightnessctl \
    ddcutil \
    wl-clipboard \
    grim \
    slurp \
    mako \
    fonts-ttf-hack \
    fonts-ttf-noto-emoji \
    fonts-ttf-dejavu \
    adobe-source-code-pro-fonts

# Optional on current Rock/OMV; install-hyprshutdown.sh builds it if missing.
if dnf list --available hyprshutdown >/dev/null 2>&1 || rpm -q hyprshutdown >/dev/null 2>&1; then
    ensure_packages hyprshutdown
fi

disable_service sddm.service
disable_service plasma6-sddm.service
enable_service ly.service

# Bind unit for graphical-session.target. ly launches Hyprland.desktop, which
# never starts that target. Hyprland exec-once starts this unit; do not enable
# it for default.target (linger would claim a graphical session at boot).
src_unit="${SETUP_FILES_DIR}/hypr/hyprland-session.service"
dest_unit="${DOTFILES_HOME}/.config/systemd/user/hyprland-session.service"
[[ -f "$src_unit" ]] || die "missing ${src_unit}"
ensure_dir "${DOTFILES_HOME}/.config/systemd/user"
if [[ ! -f "$dest_unit" ]] || ! cmp -s "$src_unit" "$dest_unit"; then
    log "user unit ${dest_unit}"
    run install -m 0644 "$src_unit" "$dest_unit"
fi
if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
    systemctl --user daemon-reload
fi
