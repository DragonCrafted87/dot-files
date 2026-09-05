#!/usr/bin/env bash
# 1080p GRUB menu and a larger virtual-console font so the firmware
# screens are readable on HiDPI panels.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

ensure_packages kbd
if dnf list --available terminus-fonts >/dev/null 2>&1 || rpm -q terminus-fonts >/dev/null 2>&1; then
    ensure_packages terminus-fonts
elif dnf list --available fonts-terminus >/dev/null 2>&1 || rpm -q fonts-terminus >/dev/null 2>&1; then
    ensure_packages fonts-terminus
else
    log "no terminus console font package; using kbd sun32"
fi

set_grub_key() {
    local key="$1"
    local value="$2"
    local file="/etc/default/grub"
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        printf 'dry-run: %s=%s in %s\n' "$key" "$value" "$file"
        return 0
    fi
    if [[ ! -f "$file" ]]; then
        warn "${file} missing; skip GRUB ${key}"
        return 0
    fi
    if grep -qE "^${key}=" "$file"; then
        if grep -qE "^${key}=${value}$" "$file"; then
            return 0
        fi
        log "set ${key}=${value} in ${file}"
        sudo sed -i -E "s|^${key}=.*|${key}=${value}|" "$file"
    else
        log "add ${key}=${value} to ${file}"
        printf '%s=%s\n' "$key" "$value" | sudo tee -a "$file" >/dev/null
    fi
}

set_grub_key GRUB_GFXMODE 1920x1080
set_grub_key GRUB_GFXPAYLOAD_LINUX keep
set_grub_key GRUB_TERMINAL_OUTPUT gfxterm

if [[ "${DOTFILES_DRY_RUN:-0}" != "1" && -f /etc/default/grub ]]; then
    cfg=""
    for candidate in /boot/grub2/grub.cfg /boot/efi/EFI/openmandriva/grub.cfg /boot/efi/EFI/OpenMandriva/grub.cfg; do
        if [[ -f "$candidate" ]]; then
            cfg="$candidate"
            break
        fi
    done
    if [[ -z "$cfg" ]]; then
        cfg="/boot/grub2/grub.cfg"
    fi
    log "grub2-mkconfig -o ${cfg}"
    sudo grub2-mkconfig -o "$cfg"
fi

vconsole="/etc/vconsole.conf"
# sun32 is shipped with kbd; terminus is nicer if the package installed.
font="latarcyrheb-sun32"
if [[ -f /usr/lib/kbd/consolefonts/ter-v32n.psf.gz || -f /usr/share/kbd/consolefonts/ter-v32n.psf.gz ]]; then
    font="ter-v32n"
fi
if [[ -f "$vconsole" ]] && grep -qE "^FONT=${font}$" "$vconsole"; then
    :
else
    log "console font ${font}"
    if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
        if [[ -f "$vconsole" ]] && grep -qE "^FONT=" "$vconsole"; then
            sudo sed -i -E "s|^FONT=.*|FONT=${font}|" "$vconsole"
        else
            printf 'FONT=%s\n' "$font" | sudo tee -a "$vconsole" >/dev/null
        fi
    fi
fi
