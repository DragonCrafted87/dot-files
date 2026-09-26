#!/usr/bin/env bash
# Apply Kitty Tango Dark to apps whose ~/.config dir already exists so
# link-user-config will not replace it (Remmina profiles, VLC, GTK).

set -euo pipefail
# shellcheck disable=SC1091
. "${REPO_ROOT:-$DOTFILES_ROOT}/setup/lib/lib.sh"

require_user

copy_if_changed() {
    local src="$1"
    local dest="$2"
    [[ -f "$src" ]] || return 0
    ensure_dir "$(dirname "$dest")"
    if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
        return 0
    fi
    log "write ${dest}"
    if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
        install -m 0644 "$src" "$dest"
    fi
}

# GTK: if the linker already symlinked the dir, leave it. Otherwise drop files.
for gtk in gtk-3.0 gtk-4.0; do
    dest_dir="${CONFIG_TARGET_DIR}/${gtk}"
    if [[ -L "$dest_dir" ]]; then
        continue
    fi
    copy_if_changed "${CONFIG_SOURCE_DIR}/${gtk}/settings.ini" "${dest_dir}/settings.ini"
    copy_if_changed "${CONFIG_SOURCE_DIR}/${gtk}/gtk.css" "${dest_dir}/gtk.css"
done

# Remmina: merge color keys into remmina.pref; do not delete profiles.
remmina_src="${CONFIG_SOURCE_DIR}/remmina/remmina.pref"
remmina_dest="${CONFIG_TARGET_DIR}/remmina/remmina.pref"
if [[ -f "$remmina_src" ]]; then
    ensure_dir "$(dirname "$remmina_dest")"
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        log "dry-run: merge remmina.pref colors"
    else
        python3 - "$remmina_src" "$remmina_dest" <<'PY'
import sys
from pathlib import Path

src, dest = Path(sys.argv[1]), Path(sys.argv[2])
incoming = {}
section = None
for line in src.read_text().splitlines():
    s = line.strip()
    if s.startswith("[") and s.endswith("]"):
        section = s
        continue
    if section == "[remmina_pref]" and "=" in line and not s.startswith("#"):
        k, _, v = line.partition("=")
        incoming[k.strip()] = v
text = dest.read_text() if dest.exists() else "[remmina_pref]\n"
lines = text.splitlines()
out = []
seen = set()
in_pref = False
for line in lines:
    s = line.strip()
    if s.startswith("[") and s.endswith("]"):
        if in_pref:
            for k, v in incoming.items():
                if k not in seen:
                    out.append(f"{k}={v}")
                    seen.add(k)
        in_pref = s == "[remmina_pref]"
        out.append(line)
        continue
    if in_pref and "=" in line and not s.startswith("#"):
        k, _, _ = line.partition("=")
        k = k.strip()
        if k in incoming:
            out.append(f"{k}={incoming[k]}")
            seen.add(k)
            continue
    out.append(line)
if not any(l.strip() == "[remmina_pref]" for l in out):
    out.append("[remmina_pref]")
for k, v in incoming.items():
    if k not in seen:
        out.append(f"{k}={v}")
new = "\n".join(out) + "\n"
if new != text:
    dest.write_text(new)
PY
        log "merge remmina.pref colors"
    fi
fi

# VLC: only stamp Fusion / tray keys. Do not replace a harvested vlcrc.
vlc_dest="${CONFIG_TARGET_DIR}/vlc/vlcrc"
if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
    log "dry-run: ensure VLC qt-style=Fusion"
else
    ensure_dir "$(dirname "$vlc_dest")"
    python3 - "$vlc_dest" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
text = p.read_text() if p.exists() else ""
wanted = {
    "qt-style": "Fusion",
    "qt-privacy-ask": "0",
    "qt-bgcone": "0",
}
lines = text.splitlines()
found = set()
out = []
for line in lines:
    s = line.strip()
    if s.startswith("#"):
        out.append(line)
        continue
    if "=" in s:
        k, _, _ = s.partition("=")
        k = k.strip()
        if k in wanted:
            out.append(f"{k}={wanted[k]}")
            found.add(k)
            continue
    out.append(line)
missing = [k for k in wanted if k not in found]
if missing:
    if out and out[-1] != "":
        out.append("")
    out.append("[qt]")
    for k in missing:
        out.append(f"{k}={wanted[k]}")
new = ("\n".join(out) + "\n") if out else ""
if new != text:
    p.write_text(new)
PY
    log "ensure VLC Fusion style"
fi
