#!/usr/bin/env bash
# Install one MakeMKV launcher and write preferred settings.

set -euo pipefail

MARKER="X-DotFiles-MakeMKV"
DESKTOP_DIR="${XDG_DESKTOP_DIR:-}"
if [[ -z "$DESKTOP_DIR" ]] && command -v xdg-user-dir >/dev/null 2>&1; then
    DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
fi
DESKTOP_DIR="${DESKTOP_DIR:-$HOME/Desktop}"
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
SETTINGS="${HOME}/.MakeMKV/settings.conf"
DEST_DIR="${MAKEMKV_DEST_DIR:-/home/dragon/Network/Storage/Media/new-unsorted}"
# Video always; every English audio and subtitle track; covers; no MVC 3D.
SELECTION='-sel:all,+sel:video,+sel:(audio&eng),+sel:(subtitle&eng),+sel:attachment,-sel:mvcvideo'
# NAME2/CMNT2: fully cleaned (spaces become underscores; MakeMKV has no hyphen cleanse).
# Date only when present (yyyy-mm-dd). Source id when present. Hyphen separators.
FILENAME='{NAME2}{-:CMNT2}{-:DY}{-:DM}{-:DD}{-:SN}{title:+DFLT}'

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
            [[ "$(basename "$file")" == "MakeMKV.desktop" ]] && continue
            rm -f "$file"
        fi
    done
}

set_makemkv_pref() {
    local key="$1"
    local value="$2"
    mkdir -p "$(dirname "$SETTINGS")"
    touch "$SETTINGS"
    if grep -q "^${key}[[:space:]]*=" "$SETTINGS"; then
        # Escape replacement for sed: keep quotes in the file value.
        local escaped
        escaped="$(printf '%s' "$value" | sed -e 's/[\\/&]/\\&/g')"
        sed -i "s|^${key}[[:space:]]*=.*|${key} = \"${escaped}\"|" "$SETTINGS"
    else
        printf '%s = "%s"\n' "$key" "$value" >>"$SETTINGS"
    fi
}

write_makemkv_prefs() {
    set_makemkv_pref io_SingleDrive "1"
    set_makemkv_pref app_ExpertMode "1"
    set_makemkv_pref app_PreferredLanguage "eng"
    set_makemkv_pref app_DestinationType "2"
    set_makemkv_pref app_DestinationDir "$DEST_DIR"
    set_makemkv_pref app_DefaultSelectionString "$SELECTION"
    set_makemkv_pref app_DefaultOutputFileName "$FILENAME"
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
write_makemkv_prefs
refresh_desktop_cache
