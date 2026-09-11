#!/usr/bin/env bash
# Give Dolphin / xdg-open a MIME map after plasma-workspace is removed.
# Hyprland env (XDG_CURRENT_DESKTOP=Hyprland:KDE) is the other half.
# That KDE tag also flips Dolphin 25.04 to single-click and binds
# double-click to "nothing", so this module pins SingleClick=false.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

src="${SETUP_FILES_DIR}/mime/mimeapps.list"
dest="${CONFIG_TARGET_DIR}/mimeapps.list"
menu_src="${SETUP_FILES_DIR}/mime/applications.menu"
menu_dest="${CONFIG_TARGET_DIR}/menus/applications.menu"

if [[ ! -f "$src" ]]; then
    die "missing ${src}"
fi

ensure_dir "${CONFIG_TARGET_DIR}"
ensure_dir "${CONFIG_TARGET_DIR}/menus"

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

# Merge SingleClick=false into kdeglobals / dolphinrc without clobbering.
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

ensure_kde_key "${CONFIG_TARGET_DIR}/kdeglobals" KDE SingleClick false
ensure_kde_key "${CONFIG_TARGET_DIR}/dolphinrc" KDE SingleClick false

if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
    exit 0
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
