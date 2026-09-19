#!/usr/bin/env bash
# LibreOffice apps, CUPS, and the harvested printer queue.
# Avoid task-printing and the libreoffice metapackage; those pull Java,
# nmap, and a pile of unneeded printer drivers.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

ensure_packages \
    cups \
    cups-filters \
    cups-browsed \
    libreoffice-writer \
    libreoffice-calc \
    libreoffice-impress \
    libreoffice-draw \
    libreoffice-math \
    libreoffice-common

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

configure_libreoffice() {
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

configure_libreoffice
configure_okular

cups_src="${SETUP_FILES_DIR}/cups"
if [[ ! -f "${cups_src}/printers.conf" ]]; then
    warn "no harvested printer config at ${cups_src}/printers.conf"
    warn "on the current workstation run: ${SETUP_DIR}/utility/harvest-cups.sh"
    enable_service cups.socket
    enable_service cups.service
    exit 0
fi

log "install printer config from ${cups_src}"
if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
    exit 0
fi

sudo systemctl stop cups-browsed.service cups.service cups.socket 2>/dev/null || true
sudo install -d -m 0755 /etc/cups /etc/cups/ppd
sudo install -m 0640 "${cups_src}/printers.conf" /etc/cups/printers.conf
if [[ -d "${cups_src}/ppd" ]]; then
    sudo cp -a "${cups_src}/ppd/." /etc/cups/ppd/
fi
if [[ -f "${cups_src}/classes.conf" ]]; then
    sudo install -m 0640 "${cups_src}/classes.conf" /etc/cups/classes.conf
fi

sudo systemctl reset-failed cups.socket cups.service cups-browsed.service 2>/dev/null || true
sleep 1
enable_service cups.socket
enable_service cups.service
if ! sudo systemctl start cups.socket cups.service; then
    sudo systemctl reset-failed cups.socket cups.service
    sleep 2
    sudo systemctl start cups.socket cups.service
fi
sudo systemctl enable --now cups-browsed.service 2>/dev/null || true
