#!/usr/bin/env bash
# Bring Bluetooth up before ly so a paired keyboard works on the login
# screen. Also apply the common BlueZ knobs that avoid
# br-connection-create-socket on reconnect.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

ensure_packages bluez
if dnf list --available bluez-tools >/dev/null 2>&1 || rpm -q bluez-tools >/dev/null 2>&1; then
    ensure_packages bluez-tools
fi
if dnf list --available blueman >/dev/null 2>&1 || rpm -q blueman >/dev/null 2>&1; then
    ensure_packages blueman
fi

enable_service bluetooth.service

if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
    run sudo systemctl start bluetooth.service || true
    if command -v rfkill >/dev/null; then
        run sudo rfkill unblock bluetooth || true
    fi
    printf 'hidp\n' | sudo tee /etc/modules-load.d/hidp.conf >/dev/null
    run sudo modprobe hidp || true
    if getent group bluetooth >/dev/null; then
        if ! id -nG "${DOTFILES_USER}" | grep -qw bluetooth; then
            log "add ${DOTFILES_USER} to bluetooth group"
            sudo usermod -aG bluetooth "${DOTFILES_USER}"
        fi
    fi
fi

set_ini_key() {
    local file="$1"
    local section="$2"
    local key="$3"
    local value="$4"
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        printf 'dry-run: [%s] %s=%s in %s\n' "$section" "$key" "$value" "$file"
        return 0
    fi
    if [[ ! -f "$file" ]]; then
        printf '[%s]\n%s=%s\n' "$section" "$key" "$value" | sudo tee "$file" >/dev/null
        return 0
    fi
    python3 - "$file" "$section" "$key" "$value" <<'PY'
import sys
from pathlib import Path
path, section, key, value = sys.argv[1:]
text = Path(path).read_text()
lines = text.splitlines()
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
        in_section = stripped[1:-1] == section
        if in_section:
            seen_section = True
        out.append(line)
        continue
    if in_section and stripped.startswith(f"{key}=") or in_section and stripped.startswith(f"# {key}="):
        out.append(f"{key}={value}")
        written = True
        continue
    out.append(line)
if in_section and not written:
    out.append(f"{key}={value}")
    written = True
if not seen_section:
    out.append(f"[{section}]")
    out.append(f"{key}={value}")
Path("/tmp/omv-bluetooth-main.conf").write_text("\n".join(out) + "\n")
PY
    sudo install -m 0644 /tmp/omv-bluetooth-main.conf "$file"
}

main_conf="/etc/bluetooth/main.conf"
set_ini_key "$main_conf" General FastConnectable true
set_ini_key "$main_conf" General JustWorksRepairing always
set_ini_key "$main_conf" General Experimental true
set_ini_key "$main_conf" Policy AutoEnable true

# USB adapters often drop HID reconnects when autosuspend is on.
grub="/etc/default/grub"
if [[ -f "$grub" ]] && ! grep -q 'btusb.enable_autosuspend=0' "$grub"; then
    log "add btusb.enable_autosuspend=0 to GRUB_CMDLINE_LINUX"
    if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
        sudo sed -i -E 's|^(GRUB_CMDLINE_LINUX=")(.*)(")$|\1\2 btusb.enable_autosuspend=0\3|' "$grub"
        if ! grep -q 'btusb.enable_autosuspend=0' "$grub"; then
            printf 'GRUB_CMDLINE_LINUX="btusb.enable_autosuspend=0"\n' | sudo tee -a "$grub" >/dev/null
        fi
        cfg="/boot/grub2/grub.cfg"
        [[ -f "$cfg" ]] && sudo grub2-mkconfig -o "$cfg"
    fi
fi

ensure_systemd_dropin ly.service bluetooth $'[Unit]\nWants=bluetooth.service\nAfter=bluetooth.service\n'

if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
    run sudo systemctl daemon-reload
    run sudo systemctl restart bluetooth.service || true
fi
