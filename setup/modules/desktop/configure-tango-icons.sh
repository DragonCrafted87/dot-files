#!/usr/bin/env bash
# Fetch the last official Tango icon tarball into ~/.local/share/icons/Tango.
# Not in Rock repos. Missing modern icons fall through to breeze-dark.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib.sh"

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

dest="${DOTFILES_HOME}/.local/share/icons/Tango"
cache="${DOTFILES_HOME}/.cache/dot-files"
tarball="${cache}/tango-icon-theme-0.8.90.tar.gz"
url="https://tango.freedesktop.org/releases/tango-icon-theme-0.8.90.tar.gz"

if [[ ! -f "${dest}/index.theme" ]]; then
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        log "dry-run: fetch Tango icon theme"
    else
        ensure_dir "$cache"
        if [[ ! -f "$tarball" ]]; then
            log "download tango-icon-theme-0.8.90"
            if ! curl -fsSL "$url" -o "$tarball"; then
                warn "could not fetch ${url}; leave Icons=breeze-dark"
            fi
        fi
        if [[ -f "$tarball" ]]; then
            tmp="$(mktemp -d)"
            tar -xzf "$tarball" -C "$tmp"
            src="$(find "$tmp" -maxdepth 2 -type d -name 'tango-icon-theme-*' | head -n1)"
            if [[ -n "$src" ]]; then
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
                fi
                if grep -q '^Inherits=' "${dest}/index.theme"; then
                    sed -i -E 's|^Inherits=.*|Inherits=breeze-dark,hicolor|' "${dest}/index.theme"
                else
                    printf '\nInherits=breeze-dark,hicolor\n' >>"${dest}/index.theme"
                fi
                log "installed Tango icons -> ${dest}"
            else
                warn "tango tarball layout unexpected"
            fi
            rm -rf "$tmp"
        fi
    fi
else
    log "Tango icons already at ${dest}"
fi

if [[ -f "${dest}/index.theme" ]]; then
    ensure_ini_key "${CONFIG_TARGET_DIR}/kdeglobals" Icons Theme Tango
fi
