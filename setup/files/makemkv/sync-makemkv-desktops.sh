#!/usr/bin/env bash
# Install one MakeMKV launcher and drop any leftover per-drive shortcuts.
# Also enable Preferences > IO > Ask for single drive mode so the GUI
# prompts for a drive when more than one optical device is attached.

set -euo pipefail

MARKER="X-DotFiles-MakeMKV"
DESKTOP_DIR="${XDG_DESKTOP_DIR:-}"
if [[ -z "$DESKTOP_DIR" ]] && command -v xdg-user-dir >/dev/null 2>&1; then
    DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
fi
DESKTOP_DIR="${DESKTOP_DIR:-$HOME/Desktop}"
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
SETTINGS="${HOME}/.MakeMKV/settings.conf"

write_launcher() {
    local dest="$1"
    cat >"$dest" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=MakeMKV
Comment=Rip a DVD or Blu-ray (asks which drive when more than one is attached)
Exec=makemkv
Icon=makemkv
Terminal=false
Categories=AudioVideo;DiscBurning;
StartupNotify=true
${MARKER}=1
EOF
    chmod 0755 "$dest"
}

prune_old_drive_launchers() {
    local dir="$1"
    local file
    shopt -s nullglob
    for file in "$dir"/MakeMKV-*.desktop "$dir"/MakeMKV.desktop; do
        [[ -f "$file" ]] || continue
        if grep -qE "^(X-DotFiles-MakeMKV-Drive=|${MARKER}=)" "$file" 2>/dev/null; then
            # Keep the single canonical launcher written below.
            [[ "$(basename "$file")" == "MakeMKV.desktop" ]] && continue
            rm -f "$file"
        fi
    done
}

enable_single_drive_mode() {
    mkdir -p "$(dirname "$SETTINGS")"
    if [[ ! -f "$SETTINGS" ]]; then
        printf 'io_SingleDrive = "1"\n' >"$SETTINGS"
        return
    fi
    if grep -q '^io_SingleDrive' "$SETTINGS"; then
        sed -i 's/^io_SingleDrive.*/io_SingleDrive = "1"/' "$SETTINGS"
    else
        printf '\nio_SingleDrive = "1"\n' >>"$SETTINGS"
    fi
}

refresh_desktop_cache() {
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true
    fi
    if command -v xdg-desktop-menu >/dev/null 2>&1; then
        xdg-desktop-menu forceupdate >/dev/null 2>&1 || true
    fi
}

mkdir -p "$DESKTOP_DIR" "$APPS_DIR"
prune_old_drive_launchers "$DESKTOP_DIR"
prune_old_drive_launchers "$APPS_DIR"
write_launcher "${DESKTOP_DIR}/MakeMKV.desktop"
write_launcher "${APPS_DIR}/MakeMKV.desktop"
enable_single_drive_mode
refresh_desktop_cache
