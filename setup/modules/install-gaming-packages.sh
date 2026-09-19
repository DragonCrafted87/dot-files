#!/usr/bin/env bash
# Workstation-only gaming stack. Needs Rock Non-free for Steam.
# Proton games should launch through
# ~/.config/hypr/scripts/steam-proton-wrap.sh so they follow the active
# Hyprland display profile (desk / theater / laptop panel).

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user
ensure_packages \
    steam \
    wine \
    gamescope \
    dxvk \
    protonplus

ensure_ini_key() {
    local file="$1"
    local section="$2"
    local key="$3"
    local value="$4"
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        log "dry-run: ${file} [${section}] ${key}=${value}"
        return 0
    fi
    python3 - "$file" "$section" "$key" "$value" <<'PY'
import sys
from pathlib import Path

path, section, key, value = sys.argv[1:]
p = Path(path)
text = p.read_text() if p.exists() else ""
lines = text.splitlines()
header = f"[{section}]"
out = []
in_section = False
seen_section = False
written = False
for line in lines:
    stripped = line.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        if in_section and not written:
            out.append(f"{key}={value}")
            written = True
        in_section = stripped == header
        if in_section:
            seen_section = True
        out.append(line)
        continue
    if in_section and stripped.startswith(f"{key}="):
        out.append(f"{key}={value}")
        written = True
        continue
    out.append(line)
if seen_section:
    if not written:
        out.append(f"{key}={value}")
else:
    if out and out[-1] != "":
        out.append("")
    out.append(header)
    out.append(f"{key}={value}")
p.parent.mkdir(parents=True, exist_ok=True)
new = "\n".join(out) + "\n"
if new != text:
    p.write_text(new)
PY
}

find_multimc_root() {
    local d
    for d in \
        "${DOTFILES_HOME}/MultiMC" \
        "${DOTFILES_HOME}/multimc" \
        "${DOTFILES_HOME}/.local/share/multimc" \
        "${DOTFILES_HOME}/.multimc" \
        "${DOTFILES_HOME}/games/MultiMC" \
        "${DOTFILES_HOME}/games/multimc" \
        "${DOTFILES_HOME}/Games/MultiMC"; do
        if [[ -f "${d}/multimc.cfg" || -x "${d}/MultiMC" || -x "${d}/multimc" || -x "${d}/bin/multimc" ]]; then
            printf '%s\n' "$d"
            return 0
        fi
    done
    return 1
}

configure_multimc() {
    local root
    root="$(find_multimc_root || true)"
    if [[ -z "$root" ]]; then
        log "MultiMC not found; skip theme and desktop"
        return 0
    fi
    log "MultiMC root ${root}"
    ensure_dir "${root}/themes/custom"
    local src_json="${SETUP_FILES_DIR}/multimc/theme.json"
    local src_css="${SETUP_FILES_DIR}/multimc/themeStyle.css"
    if [[ -f "$src_json" ]]; then
        if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
            install -m 0644 "$src_json" "${root}/themes/custom/theme.json"
            install -m 0644 "$src_css" "${root}/themes/custom/themeStyle.css"
        fi
        log "write MultiMC custom theme"
    fi
    local cfg="${root}/multimc.cfg"
    if [[ -f "$cfg" || "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        ensure_ini_key "$cfg" General ApplicationTheme custom
        ensure_ini_key "$cfg" General IconTheme pe_colored
    fi

    local bin=""
    for candidate in "${root}/MultiMC" "${root}/multimc" "${root}/bin/multimc" "${root}/MultiMC5"; do
        if [[ -x "$candidate" ]]; then
            bin="$candidate"
            break
        fi
    done
    [[ -n "$bin" ]] || return 0

    local icon_src="${SETUP_FILES_DIR}/multimc/multimc.png"
    local icon_dest="${DOTFILES_HOME}/.local/share/icons/hicolor/scalable/apps/multimc.png"
    if [[ -f "$icon_src" && "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
        ensure_dir "$(dirname "$icon_dest")"
        install -m 0644 "$icon_src" "$icon_dest"
        if command -v gtk-update-icon-cache >/dev/null 2>&1; then
            gtk-update-icon-cache -f "${DOTFILES_HOME}/.local/share/icons/hicolor" >/dev/null 2>&1 || true
        fi
    fi

    local desk="/tmp/multimc.desktop"
    cat >"$desk" <<EOF
[Desktop Entry]
Type=Application
Name=MultiMC
Comment=Minecraft launcher
Exec=${bin}
Icon=multimc
Terminal=false
Categories=Game;
StartupNotify=true
EOF
    if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
        install_user_desktop "$desk"
    fi
    rm -f "$desk"
}

configure_multimc
