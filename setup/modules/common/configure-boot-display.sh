#!/usr/bin/env bash
# 1080p GRUB menu and a larger virtual-console font so the firmware
# screens are readable on HiDPI panels. GRUB menu colors and the VT
# 16-color palette follow Kitty Tango Dark. No Plymouth splash so the
# console is visible on boot and shutdown.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib.sh"

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

unset_grub_key() {
    local key="$1"
    local file="$2"
    [[ -f "$file" ]] || return 0
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        log "dry-run: drop ${key} from ${file}"
        return 0
    fi
    if grep -qE "^[#]*[[:space:]]*${key}=" "$file"; then
        log "comment out ${key} in ${file}"
        sudo sed -i -E "s|^[#]*[[:space:]]*${key}=.*|# ${key} cleared by dot-files|" "$file"
    fi
}

strip_grub_theme_from_cfg() {
    local cfg="$1"
    [[ -f "$cfg" ]] || return 0
    log "strip OM theme/background/missing fonts from ${cfg}"
    sudo sed -i \
        -e '/loadfont .*themes\/OpenMandriva/d' \
        -e '/background_image/d' \
        -e '/^[[:space:]]*set theme=/d' \
        -e '/^[[:space:]]*export theme/d' \
        "$cfg"
}

rewrite_kernel_cmdline() {
    local file="/etc/default/grub"
    [[ -f "$file" ]] || return 0
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        log "dry-run: strip splash/quiet from GRUB_CMDLINE_*"
        return 0
    fi
    sudo python3 - "$file" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
drop = {"quiet", "splash", "rhgb"}
add = ["plymouth.enable=0", "rd.plymouth=0", "logo.nologo"]

def rewrite(val: str) -> str:
    raw = val.strip().strip("'\"")
    tokens = [t for t in raw.split() if t and t not in drop]
    seen = set(tokens)
    for extra in add:
        if extra not in seen:
            tokens.append(extra)
            seen.add(extra)
    out = []
    for t in tokens:
        if t.startswith("rd.systemd.show_status="):
            out.append("rd.systemd.show_status=1")
        elif t.startswith("systemd.show_status="):
            out.append("systemd.show_status=1")
        else:
            out.append(t)
    return '"' + " ".join(out) + '"'

lines = []
for line in text.splitlines():
    if line.startswith("GRUB_CMDLINE_LINUX_DEFAULT="):
        lines.append("GRUB_CMDLINE_LINUX_DEFAULT=" + rewrite(line.split("=", 1)[1]))
    elif line.startswith("GRUB_CMDLINE_LINUX=") and "GRUB_CMDLINE_LINUX_DEFAULT" not in line:
        lines.append("GRUB_CMDLINE_LINUX=" + rewrite(line.split("=", 1)[1]))
    else:
        lines.append(line)
path.write_text("\n".join(lines) + "\n")
PY
    log "GRUB cmdline: no quiet/splash, plymouth.enable=0"
}

set_grub_key GRUB_GFXMODE 1920x1080
set_grub_key GRUB_GFXPAYLOAD_LINUX keep
set_grub_key GRUB_TERMINAL_OUTPUT gfxterm
set_grub_key GRUB_COLOR_NORMAL '"light-gray/black"'
set_grub_key GRUB_COLOR_HIGHLIGHT '"white/blue"'
rewrite_kernel_cmdline

unset_grub_key GRUB_THEME /etc/default/grub
unset_grub_key GRUB_BACKGROUND /etc/default/grub
if [[ -d /etc/default/grub.d ]]; then
    for dropin in /etc/default/grub.d/*; do
        [[ -f "$dropin" ]] || continue
        unset_grub_key GRUB_THEME "$dropin"
        unset_grub_key GRUB_BACKGROUND "$dropin"
    done
fi

if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
    if [[ -d /boot/grub2/themes/OpenMandriva && ! -d /boot/grub2/themes/OpenMandriva.distro ]]; then
        log "move /boot/grub2/themes/OpenMandriva aside"
        sudo mv /boot/grub2/themes/OpenMandriva /boot/grub2/themes/OpenMandriva.distro
    fi
    if [[ -f /etc/grub.d/05_theme && -x /etc/grub.d/05_theme ]]; then
        log "chmod -x /etc/grub.d/05_theme"
        sudo chmod a-x /etc/grub.d/05_theme
    fi
    for script in /etc/grub.d/*theme* /etc/grub.d/*omv* /etc/grub.d/*background* /etc/grub.d/*splash*; do
        if [[ -f "$script" && -x "$script" ]]; then
            log "chmod -x ${script}"
            sudo chmod a-x "$script" || true
        fi
    done
fi

if [[ "${DOTFILES_DRY_RUN:-0}" != "1" && -f /etc/default/grub ]]; then
    cfg="/boot/grub2/grub.cfg"
    log "grub2-mkconfig -o ${cfg}"
    sudo grub2-mkconfig -o "$cfg"
    strip_grub_theme_from_cfg "$cfg"
    if [[ -f /boot/efi/EFI/openmandriva/grub.cfg ]]; then
        strip_grub_theme_from_cfg /boot/efi/EFI/openmandriva/grub.cfg
    fi
fi

vconsole="/etc/vconsole.conf"
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

palette_src="${SETUP_FILES_DIR}/vconsole/tango-dark.rgb"
palette_dest="/etc/vconsole-palette"
if [[ -f "$palette_src" ]]; then
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        log "dry-run: install ${palette_dest}"
    else
        if [[ ! -f "$palette_dest" ]] || ! cmp -s "$palette_src" "$palette_dest"; then
            log "install ${palette_dest}"
            sudo install -m 0644 "$palette_src" "$palette_dest"
        fi
        if command -v setvtrgb >/dev/null 2>&1; then
            # Redirects on the sudo line run as the user and fail on /dev/ttyN.
            # setvtrgb as root applies the table without per-tty stdin.
            log "setvtrgb ${palette_dest}"
            sudo setvtrgb "$palette_dest" || true
        fi
    fi
fi

if command -v plymouth-set-default-theme >/dev/null 2>&1 || rpm -q plymouth >/dev/null 2>&1; then
    log "disable Plymouth splash"
    if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
        sudo systemctl mask plymouth-start.service plymouth-read-write.service \
            plymouth-quit.service plymouth-quit-wait.service plymouth-kexec.service \
            plymouth-reboot.service plymouth-poweroff.service plymouth-halt.service \
            2>/dev/null || true
        if command -v plymouth-set-default-theme >/dev/null 2>&1; then
            sudo plymouth-set-default-theme -R details 2>/dev/null || \
                sudo plymouth-set-default-theme -R text 2>/dev/null || true
        fi
        if command -v dracut >/dev/null 2>&1; then
            log "rebuild initramfs so Plymouth is gone from early boot"
            sudo dracut -f || warn "dracut -f failed; next kernel install will rebuild"
        fi
    fi
else
    log "plymouth not installed"
fi
