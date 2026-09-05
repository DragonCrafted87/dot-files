#!/usr/bin/env bash
# Blank unused consoles and the Ly login screen after 15 minutes so a
# parked workstation does not burn a static prompt into the panel.
#
# Covers:
#   * kernel VT blanking (consoleblank=900, live + GRUB)
#   * every getty@ via a systemd drop-in (setterm)
#   * Ly inactivity_cmd / inactivity_delay when Ly is installed
#     (config.ini or config.lua)

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

BLANK_MINUTES="${CONSOLE_BLANK_MINUTES:-15}"
BLANK_SECONDS="$((BLANK_MINUTES * 60))"
SETTERM_BIN="$(command -v setterm || true)"
[[ -n "$SETTERM_BIN" ]] || SETTERM_BIN="/usr/bin/setterm"

ensure_grub_cmdline_arg() {
    local arg="$1"
    local file="/etc/default/grub"
    local key line current rebuilt
    local changed=0

    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        printf 'dry-run: ensure %s in %s\n' "$arg" "$file"
        return 0
    fi
    if [[ ! -f "$file" ]]; then
        warn "${file} missing; skip GRUB ${arg}"
        return 0
    fi

    for key in GRUB_CMDLINE_LINUX_DEFAULT GRUB_CMDLINE_LINUX; do
        if ! grep -qE "^${key}=" "$file"; then
            continue
        fi
        line="$(grep -E "^${key}=" "$file" | tail -n1)"
        current="${line#*=}"
        current="${current#\"}"
        current="${current%\"}"
        if [[ " ${current} " == *" ${arg} "* ]]; then
            return 0
        fi
        # Replace an older consoleblank=N rather than stacking two.
        rebuilt="$(printf '%s\n' "$current" | sed -E "s/consoleblank=[0-9]+//g; s/  +/ /g; s/^ //; s/ $//")"
        if [[ -n "$rebuilt" ]]; then
            rebuilt="${rebuilt} ${arg}"
        else
            rebuilt="$arg"
        fi
        log "set ${key}+=${arg} in ${file}"
        sudo sed -i -E "s|^${key}=.*|${key}=\"${rebuilt}\"|" "$file"
        changed=1
        break
    done

    if [[ "$changed" -eq 0 ]] && ! grep -qE "^GRUB_CMDLINE_LINUX=" "$file"; then
        log "add GRUB_CMDLINE_LINUX=\"${arg}\" to ${file}"
        printf 'GRUB_CMDLINE_LINUX="%s"\n' "$arg" | sudo tee -a "$file" >/dev/null
        changed=1
    fi

    if [[ "$changed" -eq 1 ]]; then
        local cfg=""
        for candidate in /boot/grub2/grub.cfg /boot/efi/EFI/openmandriva/grub.cfg /boot/efi/EFI/OpenMandriva/grub.cfg; do
            if [[ -f "$candidate" ]]; then
                cfg="$candidate"
                break
            fi
        done
        [[ -n "$cfg" ]] || cfg="/boot/grub2/grub.cfg"
        log "grub2-mkconfig -o ${cfg}"
        sudo grub2-mkconfig -o "$cfg"
    fi
}

set_ly_ini_key() {
    local file="$1"
    local key="$2"
    local value="$3"
    if grep -qE "^${key}[[:space:]]*=" "$file"; then
        if grep -qE "^${key}[[:space:]]*=[[:space:]]*${value}$" "$file"; then
            return 0
        fi
        log "set ${key} = ${value} in ${file}"
        if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
            sudo sed -i -E "s|^${key}[[:space:]]*=.*|${key} = ${value}|" "$file"
        fi
    else
        log "add ${key} = ${value} to ${file}"
        if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
            printf '%s = %s\n' "$key" "$value" | sudo tee -a "$file" >/dev/null
        fi
    fi
}

set_ly_lua_key() {
    local file="$1"
    local key="$2"
    local value="$3"
    # Matches inactivity_cmd = nil / "..." and inactivity_delay = 0
    if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$file"; then
        if grep -qE "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*${value}[[:space:]]*,?[[:space:]]*$" "$file"; then
            return 0
        fi
        log "set ${key} = ${value} in ${file}"
        if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
            sudo sed -i -E "s|^([[:space:]]*${key}[[:space:]]*=).*|\1 ${value},|" "$file"
        fi
    else
        warn "${file} has no ${key}; skip"
    fi
}

# --- kernel / live console ----------------------------------------------
ensure_grub_cmdline_arg "consoleblank=${BLANK_SECONDS}"

if [[ -f /sys/module/kernel/parameters/consoleblank ]]; then
    current_blank="$(cat /sys/module/kernel/parameters/consoleblank 2>/dev/null || echo "")"
    if [[ "$current_blank" != "$BLANK_SECONDS" ]]; then
        log "consoleblank=${BLANK_SECONDS} (live)"
        if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
            # Some kernels expose this file but reject writes. Persistent
            # blanking still comes from GRUB + the getty drop-in.
            if ! printf '%s\n' "$BLANK_SECONDS" | sudo tee /sys/module/kernel/parameters/consoleblank >/dev/null; then
                warn "kernel rejected live consoleblank write; GRUB value applies on next boot"
            fi
        fi
    fi
fi

# --- getty VTs (tty2+ when Ly is not sitting on that tty) ---------------
ensure_systemd_dropin "getty@.service" "console-blank" "$(cat <<EOF
[Service]
# setterm --blank is minutes. Powersave trips the panel off after the same delay.
ExecStartPost=-${SETTERM_BIN} --blank ${BLANK_MINUTES} --powersave powerdown --powerdown ${BLANK_MINUTES}
EOF
)"

# --- Ly login screen ----------------------------------------------------
if [[ -f /etc/ly/config.ini ]]; then
    set_ly_ini_key /etc/ly/config.ini inactivity_delay "$BLANK_SECONDS"
    set_ly_ini_key /etc/ly/config.ini inactivity_cmd "${SETTERM_BIN} --blank force"
elif [[ -f /etc/ly/config.lua ]]; then
    set_ly_lua_key /etc/ly/config.lua inactivity_delay "$BLANK_SECONDS"
    set_ly_lua_key /etc/ly/config.lua inactivity_cmd "\"${SETTERM_BIN} --blank force\""
else
    log "Ly config not present; console blanking only"
fi
