#!/usr/bin/env bash
# Give Dolphin / xdg-open a MIME map after plasma-workspace is removed.
# Hyprland env (XDG_CURRENT_DESKTOP=Hyprland:KDE) is the other half.
# That KDE tag also flips Dolphin 25.04 to single-click and binds
# double-click to "nothing", so this module pins SingleClick=false.
# Loose config/kdeglobals is applied here; link-user-config ignores files.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

src="${SETUP_FILES_DIR}/mime/mimeapps.list"
dest="${CONFIG_TARGET_DIR}/mimeapps.list"
menu_src="${SETUP_FILES_DIR}/mime/applications.menu"
menu_dest="${CONFIG_TARGET_DIR}/menus/applications.menu"
svc_src="${SETUP_FILES_DIR}/mime/servicemenus"
svc_kf6="${DOTFILES_HOME}/.local/share/kio/servicemenus"
svc_kf5="${DOTFILES_HOME}/.local/share/kservices5/ServiceMenus"
mime_xml_src="${SETUP_FILES_DIR}/mime/code-workspace.xml"
mime_xml_dest="${DOTFILES_HOME}/.local/share/mime/packages/code-workspace.xml"
theme_src="${CONFIG_SOURCE_DIR}/kdeglobals"
theme_dest="${CONFIG_TARGET_DIR}/kdeglobals"

if [[ ! -f "$src" ]]; then
    die "missing ${src}"
fi

ensure_dir "${CONFIG_TARGET_DIR}"
ensure_dir "${CONFIG_TARGET_DIR}/menus"
ensure_dir "$svc_kf6"
ensure_dir "$svc_kf5"
ensure_dir "$(dirname "$mime_xml_dest")"

write_mimeapps=0
if [[ ! -f "$dest" ]]; then
    write_mimeapps=1
elif grep -q '^# managed by dot-files configure-mime-defaults' "$dest"; then
    if ! cmp -s "$src" "$dest"; then
        write_mimeapps=1
    fi
else
    warn "leave existing ${dest} (not managed by this module)"
fi

if [[ "$write_mimeapps" -eq 1 ]]; then
    log "write ${dest}"
    if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
        install -m 0644 "$src" "$dest"
    fi
fi

if [[ -f "$menu_src" ]]; then
    if [[ ! -f "$menu_dest" ]] || ! cmp -s "$menu_src" "$menu_dest"; then
        log "write ${menu_dest}"
        if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
            install -m 0644 "$menu_src" "$menu_dest"
        fi
    fi
fi

if [[ -f "$mime_xml_src" ]]; then
    if [[ ! -f "$mime_xml_dest" ]] || ! cmp -s "$mime_xml_src" "$mime_xml_dest"; then
        log "write ${mime_xml_dest}"
        if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
            install -m 0644 "$mime_xml_src" "$mime_xml_dest"
        fi
    fi
fi

if [[ -d "$svc_src" ]]; then
    shopt -s nullglob
    for desktop in "$svc_src"/*.desktop; do
        name="$(basename "$desktop")"
        for dest_dir in "$svc_kf6" "$svc_kf5"; do
            target="${dest_dir}/${name}"
            if [[ ! -f "$target" ]] || ! cmp -s "$desktop" "$target"; then
                log "write ${target}"
                if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
                    install -m 0755 "$desktop" "$target"
                fi
            fi
        done
    done
fi

# Merge keys into kdeglobals / dolphinrc without clobbering other settings.
ensure_kde_key() {
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

seed_breeze_dark() {
    local dest_file="$1"
    local src_file="$2"

    [[ -f "$src_file" ]] || return 0
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        log "dry-run: seed Breeze Dark into ${dest_file}"
        return 0
    fi
    if [[ ! -f "$dest_file" ]]; then
        log "write ${dest_file} from ${src_file}"
        install -m 0644 "$src_file" "$dest_file"
        return 0
    fi
    if grep -q '^\[Colors:Window\]' "$dest_file"; then
        return 0
    fi
    log "append Breeze Dark color groups to ${dest_file}"
    python3 - "$dest_file" "$src_file" <<'PY'
import sys
from pathlib import Path

dest, src = Path(sys.argv[1]), Path(sys.argv[2])
text = dest.read_text() if dest.exists() else ""
src_text = src.read_text()
wanted = (
    "[Colors:Window]",
    "[Colors:View]",
    "[Colors:Button]",
    "[Colors:Selection]",
    "[Colors:Tooltip]",
    "[Colors:Complementary]",
    "[Colors:Header]",
)
blocks = []
current = None
buf = []
for line in src_text.splitlines():
    stripped = line.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        if current in wanted:
            blocks.append("\n".join(buf).rstrip())
        current = stripped
        buf = [line]
        continue
    if current in wanted:
        buf.append(line)
if current in wanted and buf:
    blocks.append("\n".join(buf).rstrip())
if not blocks:
    raise SystemExit(0)
new = text.rstrip() + "\n\n" + "\n\n".join(blocks) + "\n"
if new != text:
    dest.write_text(new)
PY
}

ensure_kde_key "${CONFIG_TARGET_DIR}/kdeglobals" KDE SingleClick false
ensure_kde_key "${CONFIG_TARGET_DIR}/dolphinrc" KDE SingleClick false
ensure_kde_key "${CONFIG_TARGET_DIR}/kdeglobals" General TerminalApplication kitty
ensure_kde_key "${CONFIG_TARGET_DIR}/kdeglobals" General TerminalService kitty.desktop
ensure_kde_key "${CONFIG_TARGET_DIR}/dolphinrc" General TerminalApplication kitty

ensure_kde_key "${CONFIG_TARGET_DIR}/kdeglobals" General ColorScheme BreezeDark
ensure_kde_key "${CONFIG_TARGET_DIR}/kdeglobals" General Name "Breeze Dark"
ensure_kde_key "${CONFIG_TARGET_DIR}/kdeglobals" General widgetStyle Fusion
ensure_kde_key "${CONFIG_TARGET_DIR}/kdeglobals" Icons Theme breeze-dark
ensure_kde_key "${CONFIG_TARGET_DIR}/kdeglobals" KDE LookAndFeelPackage org.kde.breezedark.desktop
ensure_kde_key "${CONFIG_TARGET_DIR}/kdeglobals" KDE widgetStyle Fusion
ensure_kde_key "${CONFIG_TARGET_DIR}/kdeglobals" UiSettings ColorScheme BreezeDark
seed_breeze_dark "$theme_dest" "$theme_src"

if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
    exit 0
fi

if command -v update-mime-database >/dev/null 2>&1; then
    update-mime-database "${DOTFILES_HOME}/.local/share/mime" >/dev/null 2>&1 || true
fi

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${DOTFILES_HOME}/.local/share/applications" 2>/dev/null || true
fi

if command -v kbuildsycoca6 >/dev/null 2>&1; then
    log "kbuildsycoca6"
    kbuildsycoca6 --noincremental >/dev/null 2>&1 || kbuildsycoca6 || true
elif command -v kbuildsycoca5 >/dev/null 2>&1; then
    log "kbuildsycoca5"
    kbuildsycoca5 --noincremental >/dev/null 2>&1 || kbuildsycoca5 || true
else
    warn "kbuildsycoca6 not on PATH; Dolphin may need a session restart after first install"
fi
