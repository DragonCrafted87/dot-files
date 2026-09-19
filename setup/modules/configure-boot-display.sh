#!/usr/bin/env bash
# 1080p GRUB menu and a larger virtual-console font so the firmware
# screens are readable on HiDPI panels. GRUB menu colors and the VT
# 16-color palette follow Kitty Tango Dark.

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

set_grub_key GRUB_GFXMODE 1920x1080
set_grub_key GRUB_GFXPAYLOAD_LINUX keep
set_grub_key GRUB_TERMINAL_OUTPUT gfxterm
set_grub_key GRUB_COLOR_NORMAL '"light-gray/black"'
set_grub_key GRUB_COLOR_HIGHLIGHT '"white/blue"'

# Empty GRUB_THEME="" is still a set variable; grub2-mkconfig + OM theme
# scripts keep the branded backsplash. Comment the keys out entirely and
# disable the theme drop-ins.
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
    for script in /etc/grub.d/*theme* /etc/grub.d/*omv* /etc/grub.d/*background* /etc/grub.d/*splash*; do
        if [[ -f "$script" && -x "$script" ]]; then
            log "chmod -x ${script} (distro GRUB theme)"
            sudo chmod a-x "$script" || true
        fi
    done
    # 05/08 style theme helpers on RPM distros.
    for script in /etc/grub.d/05_debian_theme /etc/grub.d/08_fallback_theme /etc/grub.d/41_custom_theme; do
        if [[ -f "$script" && -x "$script" ]]; then
            log "chmod -x ${script}"
            sudo chmod a-x "$script" || true
        fi
    done
fi

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
    # Last pass: drop leftover background_image / theme lines the scripts
    # still emitted.
    if sudo grep -qE 'background_image|set theme=' "$cfg" 2>/dev/null; then
        log "strip background_image/theme from ${cfg}"
        sudo sed -i -E '/background_image/d;/^[[:space:]]*set theme=/d;/^[[:space:]]*insmod jpeg/d;/^[[:space:]]*insmod png/d' "$cfg"
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
            for n in 1 2 3 7; do
                if [[ -c "/dev/tty${n}" ]]; then
                    sudo setvtrgb "$palette_dest" <"/dev/tty${n}" >/dev/null 2>&1 || true
                fi
            done
        fi
    fi
fi

if command -v plymouth-set-default-theme >/dev/null 2>&1; then
    current="$(plymouth-set-default-theme 2>/dev/null || true)"
    target=""
    for name in breeze-dark breeze spinner; do
        if plymouth-set-default-theme --list 2>/dev/null | grep -qx "$name"; then
            target="$name"
            break
        fi
    done
    if [[ -n "$target" && "$current" != "$target" ]]; then
        log "plymouth theme ${target} (was ${current:-none})"
        if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
            sudo plymouth-set-default-theme -R "$target" || warn "plymouth-set-default-theme failed"
        fi
    elif [[ -z "$target" ]]; then
        log "no breeze/spinner Plymouth theme packaged; leave ${current:-default}"
    fi
else
    log "plymouth not installed; skip splash theme"
fi
