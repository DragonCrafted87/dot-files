#!/usr/bin/env bash
# Tango Dark for MultiMC, LibreOffice, Okular PDFs, Brave chrome, and the
# original Tango icon theme (fetched; not in Rock repos).

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

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

install_tango_icons() {
    local dest="${DOTFILES_HOME}/.local/share/icons/Tango"
    local cache="${DOTFILES_HOME}/.cache/dot-files"
    local tarball="${cache}/tango-icon-theme-0.8.90.tar.gz"
    local url="https://tango.freedesktop.org/releases/tango-icon-theme-0.8.90.tar.gz"

    if [[ -f "${dest}/index.theme" ]]; then
        log "Tango icons already at ${dest}"
        return 0
    fi
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        log "dry-run: fetch Tango icon theme"
        return 0
    fi
    ensure_dir "$cache"
    if [[ ! -f "$tarball" ]]; then
        log "download tango-icon-theme-0.8.90"
        if ! curl -fsSL "$url" -o "$tarball"; then
            warn "could not fetch ${url}; leave Icons=breeze-dark"
            return 0
        fi
    fi
    local tmp
    tmp="$(mktemp -d)"
    tar -xzf "$tarball" -C "$tmp"
    local src
    src="$(find "$tmp" -maxdepth 2 -type d -name 'tango-icon-theme-*' | head -n1)"
    if [[ -z "$src" ]]; then
        warn "tango tarball layout unexpected"
        rm -rf "$tmp"
        return 0
    fi
    ensure_dir "$(dirname "$dest")"
    rm -rf "$dest"
    mkdir -p "$dest"
    for d in 16x16 22x22 32x32 scalable; do
        if [[ -d "${src}/${d}" ]]; then
            cp -a "${src}/${d}" "$dest/"
        fi
    done
    if [[ -f "${src}/index.theme" ]]; then
        cp "${src}/index.theme" "${dest}/index.theme"
    else
        cat >"${dest}/index.theme" <<'EOF'
[Icon Theme]
Name=Tango
Comment=Tango Desktop Project 0.8.90
Inherits=breeze-dark,hicolor
Directories=16x16/actions,22x22/actions,32x32/actions,scalable/actions
EOF
    fi
    if grep -q '^Inherits=' "${dest}/index.theme"; then
        sed -i -E 's|^Inherits=.*|Inherits=breeze-dark,hicolor|' "${dest}/index.theme"
    else
        printf '\nInherits=breeze-dark,hicolor\n' >>"${dest}/index.theme"
    fi
    rm -rf "$tmp"
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache -f "$dest" >/dev/null 2>&1 || true
    fi
    log "installed Tango icons -> ${dest} (inherits breeze-dark)"
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

    local icon_src="${SETUP_FILES_DIR}/multimc/multimc.svg"
    local icon_dest="${DOTFILES_HOME}/.local/share/icons/hicolor/scalable/apps/multimc.svg"
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

configure_libreoffice() {
    # Prefer the Qt/KDE VCL so toolbars read kdeglobals instead of Adwaita.
    local pkg
    for pkg in libreoffice-kf6 libreoffice-qt6 libreoffice-kde5 libreoffice-gtk3; do
        if dnf list --available "$pkg" >/dev/null 2>&1 || rpm -q "$pkg" >/dev/null 2>&1; then
            ensure_packages "$pkg"
            break
        fi
    done

    local xcu_src="${SETUP_FILES_DIR}/libreoffice/tango-dark.xcu"
    local dest="${CONFIG_TARGET_DIR}/libreoffice/4/user/registrymodifications.xcu"
    [[ -f "$xcu_src" ]] || return 0
    if [[ ! -f "$dest" ]]; then
        log "LibreOffice profile not created yet; skip registry inject"
        return 0
    fi
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        log "dry-run: inject LibreOffice TangoDark scheme"
        return 0
    fi
    python3 - "$xcu_src" "$dest" <<'PY'
import sys
from pathlib import Path

src, dest = Path(sys.argv[1]), Path(sys.argv[2])
snippet = src.read_text().strip()
text = dest.read_text()
skip_tokens = (
    "TangoDark",
    "ApplicationAppearance",
    "WindowColor",
    "WindowTextColor",
    "ButtonColor",
    "ButtonTextColor",
    "AccentColor",
    "BaseColor",
    "DisabledColor",
    "DisabledTextColor",
)
lines = []
for line in text.splitlines():
    if any(tok in line for tok in skip_tokens) or (
        "SymbolStyle" in line and "sifr_dark" in line
    ):
        continue
    lines.append(line)
text = "\n".join(lines)
if "</oor:items>" not in text:
    raise SystemExit(0)
text = text.replace("</oor:items>", snippet + "\n</oor:items>")
dest.write_text(text if text.endswith("\n") else text + "\n")
PY
    log "LibreOffice TangoDark + Appearance=Dark + VCL chrome colors"
}

configure_okular() {
    local dest="${CONFIG_TARGET_DIR}/okularpartrc"
    ensure_ini_key "$dest" Document ChangeColors true
    ensure_ini_key "$dest" Document RenderMode 2
    ensure_ini_key "$dest" "Dlg Accessibility" RecolorForeground "211,215,207"
    ensure_ini_key "$dest" "Dlg Accessibility" RecolorBackground "0,0,0"
}

configure_brave_theme() {
    local src="${SETUP_FILES_DIR}/brave/tango-dark.json"
    local dest="/etc/brave/policies/managed/tango-dark.json"
    [[ -f "$src" ]] || return 0
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        log "dry-run: install ${dest}"
        return 0
    fi
    sudo mkdir -p "$(dirname "$dest")"
    if [[ ! -f "$dest" ]] || ! cmp -s "$src" "$dest"; then
        log "install ${dest}"
        sudo install -m 0644 "$src" "$dest"
    fi
}

install_tango_icons
if [[ -f "${DOTFILES_HOME}/.local/share/icons/Tango/index.theme" ]]; then
    ensure_ini_key "${CONFIG_TARGET_DIR}/kdeglobals" Icons Theme Tango
fi
configure_multimc
configure_libreoffice
configure_okular
configure_brave_theme
