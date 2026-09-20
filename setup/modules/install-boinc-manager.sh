#!/usr/bin/env bash
# BOINC Manager desktop launcher and Select-computer MRU.
# Sourced from install-boinc.sh. Not a standalone role module.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

# wxGTK does not honor gtk-application-prefer-dark-theme alone.
# GTK_THEME=Adwaita:dark plus ~/.config/gtk-3.0/gtk.css is Tango Dark.
install_manager_desktop() {
    local src="${SETUP_FILES_DIR}/boinc/boincmgr.desktop"
    local dest_user="${DOTFILES_HOME}/.local/share/applications/boincmgr.desktop"
    local dest_sys=/usr/local/share/applications/boincmgr.desktop
    ensure_dir "$(dirname "$dest_user")"
    run sudo mkdir -p "$(dirname "$dest_sys")"
    if [[ -f "$src" ]]; then
        install -m 0644 "$src" "$dest_user"
        run sudo install -m 0644 "$src" "$dest_sys"
    fi
}

# Manager stores the Select computer MRU in ~/.BOINC Manager.
# Names only; the shared rpc_password is the login for every host.
write_manager_computers() {
    local cfg="${DOTFILES_HOME}/.BOINC Manager"
    local list="$1"
    if command -v pgrep >/dev/null && pgrep -u "$(id -u)" -x boincmgr >/dev/null 2>&1; then
        warn "quit boincmgr so it does not overwrite ${cfg} on exit"
    fi
    python3 - "$cfg" "$list" <<'PY'
from pathlib import Path
import sys

cfg = Path(sys.argv[1])
hosts_path = Path(sys.argv[2])
wanted = []
seen = set()
for name in ("localhost", "127.0.0.1"):
    wanted.append(name)
    seen.add(name)
if hosts_path.is_file():
    for raw in hosts_path.read_text().splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        host = line.split()[0]
        if host not in seen:
            wanted.append(host)
            seen.add(host)

existing = []
other = []
section = None
if cfg.is_file():
    for line in cfg.read_text().splitlines():
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            section = stripped[1:-1]
            if section != "ComputerMRU":
                other.append(line)
            continue
        if section == "ComputerMRU":
            if "=" in line:
                existing.append(line.split("=", 1)[1].strip())
            continue
        other.append(line)

for host in existing:
    if host and host not in seen:
        wanted.append(host)
        seen.add(host)

lines = [l for l in other if l.strip() != ""]
if lines and lines[-1] != "":
    lines.append("")
lines.append("[ComputerMRU]")
for i, host in enumerate(wanted):
    lines.append(f"{i}={host}")
lines.append("")
cfg.write_text("\n".join(lines))
print(f"updated {cfg} with {len(wanted)} computers")
PY
}
