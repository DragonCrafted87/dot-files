#!/usr/bin/env bash
# Refresh ~/Desktop launchers so only currently attached optical drives
# have a MakeMKV shortcut. Also installs copies under
# ~/.local/share/applications and refreshes the XDG desktop database so
# quickshell / other menus see them immediately.

set -euo pipefail

MARKER="X-DotFiles-MakeMKV-Drive"
DESKTOP_DIR="${XDG_DESKTOP_DIR:-}"
if [[ -z "$DESKTOP_DIR" ]] && command -v xdg-user-dir >/dev/null 2>&1; then
    DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
fi
DESKTOP_DIR="${DESKTOP_DIR:-$HOME/Desktop}"
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"

optical_nodes() {
    local node real seen=""
    shopt -s nullglob
    for node in /dev/sr[0-9]* /dev/cdrom /dev/dvd /dev/bd /dev/bluray; do
        [[ -b "$node" || -L "$node" ]] || continue
        real="$(readlink -f "$node" 2>/dev/null || printf '%s' "$node")"
        [[ -b "$real" ]] || continue
        case " $seen " in
            *" $real "*) continue ;;
        esac
        if command -v udevadm >/dev/null 2>&1; then
            if ! udevadm info --query=property --name="$real" 2>/dev/null \
                | grep -q '^ID_CDROM=1$'; then
                continue
            fi
        fi
        printf '%s\n' "$real"
        seen="$seen $real"
    done
}

drive_label() {
    local dev="$1"
    local model vendor
    model="$(udevadm info --query=property --name="$dev" 2>/dev/null | awk -F= '/^ID_MODEL=/{print $2; exit}')"
    vendor="$(udevadm info --query=property --name="$dev" 2>/dev/null | awk -F= '/^ID_VENDOR=/{print $2; exit}')"
    model="${model//_/ }"
    vendor="${vendor//_/ }"
    if [[ -n "$vendor" && -n "$model" ]]; then
        printf '%s %s (%s)\n' "$vendor" "$model" "$dev"
    elif [[ -n "$model" ]]; then
        printf '%s (%s)\n' "$model" "$dev"
    else
        printf 'Optical drive (%s)\n' "$dev"
    fi
}

slug_for() {
    local dev="$1"
    printf '%s' "$(basename "$dev")"
}

write_launcher() {
    local dest="$1"
    local dev="$2"
    local label="$3"
    cat >"$dest" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=MakeMKV — ${label}
Comment=Rip a disc in ${dev}
Exec=makemkv
Icon=makemkv
Terminal=false
Categories=AudioVideo;DiscBurning;
StartupNotify=true
${MARKER}=${dev}
EOF
    chmod 0755 "$dest"
}

prune_stale() {
    local dir="$1"
    local wanted="$2"
    local file
    shopt -s nullglob
    for file in "$dir"/MakeMKV-*.desktop; do
        grep -q "^${MARKER}=" "$file" 2>/dev/null || continue
        case " $wanted " in
            *" $file "*) continue ;;
        esac
        rm -f "$file"
    done
}

refresh_desktop_cache() {
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true
    fi
    if command -v xdg-desktop-menu >/dev/null 2>&1; then
        xdg-desktop-menu forceupdate >/dev/null 2>&1 || true
    fi
    if command -v desktop-file-validate >/dev/null 2>&1; then
        local f
        shopt -s nullglob
        for f in "$APPS_DIR"/MakeMKV-*.desktop; do
            desktop-file-validate "$f" >/dev/null 2>&1 || true
        done
    fi
}

mkdir -p "$DESKTOP_DIR" "$APPS_DIR"

wanted_desktop=""
wanted_apps=""
while IFS= read -r dev; do
    [[ -n "$dev" ]] || continue
    slug="$(slug_for "$dev")"
    label="$(drive_label "$dev")"
    dest_desktop="${DESKTOP_DIR}/MakeMKV-${slug}.desktop"
    dest_apps="${APPS_DIR}/MakeMKV-${slug}.desktop"
    write_launcher "$dest_desktop" "$dev" "$label"
    write_launcher "$dest_apps" "$dev" "$label"
    wanted_desktop="$wanted_desktop $dest_desktop"
    wanted_apps="$wanted_apps $dest_apps"
done < <(optical_nodes)

prune_stale "$DESKTOP_DIR" "$wanted_desktop"
prune_stale "$APPS_DIR" "$wanted_apps"
refresh_desktop_cache
