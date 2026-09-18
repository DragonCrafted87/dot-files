#!/usr/bin/env bash
# Dev / daily-driver extras for workstation and laptop.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

dest="/etc/yum.repos.d/vscode.repo"
if [[ ! -f "$dest" ]]; then
    log "add Visual Studio Code repo"
    if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
        sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
        sudo tee "$dest" >/dev/null <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
    fi
fi

ensure_packages \
    code \
    gcc \
    gcc-c++ \
    cmake \
    meson \
    ninja \
    docker \
    docker-compose \
    kubernetes-client \
    rclone \
    remmina \
    remmina-plugins-rdp \
    freerdp \
    solaar \
    piper \
    qalculate-gtk \
    aria2 \
    android-tools \
    guvcview

# Rock 6.0 ships plasma6-okular (KF6) and a leftover KF5 package still
# named okular. Installing the old name conflicts with the KF6 files.
install_kf6_or_plain plasma6-okular okular plasma6-okular-pdf plasma6-okular-common

# Override packaged .desktop files so the QS start menu can find Piper by
# Logitech fragments and Guvcview by camera/photo/video words. Also drop
# copies on the Desktop.
install_user_desktop() {
    local src="$1"
    local name
    local desktop_dir="${XDG_DESKTOP_DIR:-}"
    local apps_dir="${DOTFILES_HOME}/.local/share/applications"

    name="$(basename "$src")"
    [[ -f "$src" ]] || die "missing ${src}"

    if [[ -z "$desktop_dir" ]] && command -v xdg-user-dir >/dev/null 2>&1; then
        desktop_dir="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
    fi
    desktop_dir="${desktop_dir:-${DOTFILES_HOME}/Desktop}"

    ensure_dir "$desktop_dir"
    ensure_dir "$apps_dir"
    run install -m 0755 "$src" "${apps_dir}/${name}"
    run install -m 0755 "$src" "${desktop_dir}/${name}"
}

install_user_desktop "${SETUP_FILES_DIR}/applications/org.freedesktop.Piper.desktop"
install_user_desktop "${SETUP_FILES_DIR}/applications/guvcview.desktop"

if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "${DOTFILES_HOME}/.local/share/applications" >/dev/null 2>&1 || true
    fi
    if command -v xdg-desktop-menu >/dev/null 2>&1; then
        xdg-desktop-menu forceupdate >/dev/null 2>&1 || true
    fi
fi
