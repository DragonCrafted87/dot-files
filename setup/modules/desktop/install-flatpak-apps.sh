#!/usr/bin/env bash
# Role-specific Flatpaks. Discord on workstation and laptop; protontricks
# only on the workstation.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib.sh"

require_user
ensure_packages flatpak
ensure_flatpak_remote flathub https://flathub.org/repo/flathub.flatpakrepo

case "${OMV_ROLE:-}" in
    workstation)
        ensure_flatpak com.discordapp.Discord
        ensure_flatpak com.github.Matoking.protontricks
        ensure_flatpak com.obsproject.Studio
        ensure_flatpak com.obsproject.Studio.Plugin.BackgroundRemoval
        ;;
    *)
        log "no extra flatpaks for role ${OMV_ROLE:-unknown}"
        ;;
esac

# Theme via env. Binding xdg-config/gtk-3.0 makes some Flatpaks fight a
# real ~/.config/gtk-3.0 directory (now linked from the repo).
strip_gtk_filesystem_grants() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    python3 - "$file" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
lines = []
for line in text.splitlines():
    if not line.startswith("filesystems="):
        lines.append(line)
        continue
    parts = [p for p in line.split("=", 1)[1].split(";") if p]
    keep = []
    for p in parts:
        raw = p[1:] if p.startswith("!") else p
        if raw.startswith("xdg-config/gtk-3.0") or raw.startswith("xdg-config/gtk-4.0"):
            continue
        keep.append(p)
    keep.append("!xdg-config/gtk-3.0")
    keep.append("!xdg-config/gtk-4.0")
    seen = set()
    out = []
    for p in keep:
        if p not in seen:
            seen.add(p)
            out.append(p)
    lines.append("filesystems=" + ";".join(out) + ";")
path.write_text("\n".join(lines) + "\n")
PY
}

if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
    log "dry-run: flatpak override GTK/Qt theme env"
else
    log "flatpak override user theme env"
    flatpak override --user --env=GTK_THEME=Adwaita:dark || true
    flatpak override --user --env=QT_QPA_PLATFORMTHEME=kde || true
    flatpak override --user --env=XCURSOR_THEME=breeze_cursors || true
    strip_gtk_filesystem_grants "${DOTFILES_HOME}/.local/share/flatpak/overrides/global"
fi
