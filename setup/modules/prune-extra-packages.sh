#!/usr/bin/env bash
# Strip the machine down to: (ISO packages minus iso-strip.list) plus
# never-remove.list. Role packages are NOT kept here; the next plain
# role.sh run reinstalls them.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

role="${OMV_ROLE:-}"
[[ -n "$role" ]] || die "OMV_ROLE is unset; run: ./setup/role.sh --reset <role>"
valid_role "$role" || die "unknown role ${role}"

# Refuse to strip from inside Ly / Hyprland / Plasma. A graphical session
# dies mid-remove. SSH or a real VT (Ctrl+Alt+F3) only.
require_reset_session() {
    local tty_name proc reason=""
    tty_name="$(tty 2>/dev/null || true)"

    if [[ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ]]; then
        log "reset session: ssh"
        return 0
    fi
    if [[ "$tty_name" == /dev/tty[0-9]* ]]; then
        log "reset session: ${tty_name}"
        return 0
    fi

    if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        reason="HYPRLAND_INSTANCE_SIGNATURE is set"
    elif [[ -n "${WAYLAND_DISPLAY:-}" || -n "${DISPLAY:-}" ]]; then
        reason="graphical display is set (${WAYLAND_DISPLAY:-}${DISPLAY:-})"
    elif [[ "${XDG_SESSION_TYPE:-}" == wayland || "${XDG_SESSION_TYPE:-}" == x11 ]]; then
        reason="XDG_SESSION_TYPE=${XDG_SESSION_TYPE}"
    fi

    proc="$(ps -o comm= -p "${PPID}" 2>/dev/null || true)"
    case "$proc" in
        ly | Hyprland | hyprland | plasmashell | sddm | sddm-helper | kwin*)
            reason="parent process is ${proc}"
            ;;
    esac

    die "reset must run from a real VT (Ctrl+Alt+F3) or SSH, not under Ly/Hyprland/Plasma${reason:+ (${reason})}"
}

require_reset_session

list_file_names() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    grep -vE '^[[:space:]]*(#|$)' "$file" | sed 's/[[:space:]]\+$//'
}

name_is_stripped() {
    local name="$1"
    local pat
    for pat in "${STRIP_PATTERNS[@]}"; do
        # shellcheck disable=SC2254
        case "$name" in
            $pat) return 0 ;;
        esac
    done
    return 1
}

ISO_FILE="${SETUP_FILES_DIR}/packages/iso-installed.list"
STRIP_FILE="${SETUP_FILES_DIR}/packages/iso-strip.list"
KEEP_FILE="${SETUP_FILES_DIR}/packages/never-remove.list"

mapfile -t STRIP_PATTERNS < <(list_file_names "$STRIP_FILE")
mapfile -t iso_names < <(list_file_names "$ISO_FILE")
mapfile -t never < <(list_file_names "$KEEP_FILE")

declare -A keep=()
for pkg in "${iso_names[@]}"; do
    [[ -z "$pkg" ]] && continue
    if name_is_stripped "$pkg"; then
        continue
    fi
    keep["$pkg"]=1
done
for pkg in "${never[@]}"; do
    [[ -n "$pkg" ]] && keep["$pkg"]=1
done

log "baseline: ${#keep[@]} names (ISO minus strip + never-remove)"

mapfile -t installed < <(rpm -qa --qf '%{name}\n' | sort -u)
to_remove=()
for pkg in "${installed[@]}"; do
    [[ -z "$pkg" ]] && continue
    if [[ -n "${keep[$pkg]:-}" ]]; then
        continue
    fi
    case "$pkg" in
        kernel*|grub2*|systemd*|glibc*|dnf*|rpm-*|basesystem*|filesystem|setup)
            continue
            ;;
    esac
    to_remove+=("$pkg")
done

if [[ "${#to_remove[@]}" -eq 0 ]]; then
    log "already at baseline; nothing to remove"
else
    log "remove extras (${#to_remove[@]}):"
    printf '    %s\n' "${to_remove[@]}"
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        printf 'dry-run: sudo dnf remove -y %s\n' "${to_remove[*]}"
    elif [[ "${RESET_CONFIRM:-}" == "yes" ]]; then
        run sudo dnf remove -y "${to_remove[@]}"
    else
        warn "not removing; re-run with --reset --force from a VT or SSH"
    fi
fi

if command -v flatpak >/dev/null 2>&1; then
    mapfile -t installed_fps < <(flatpak list --app --columns=application 2>/dev/null | sort -u || true)
    fp_remove=()
    for app in "${installed_fps[@]}"; do
        [[ -z "$app" || "$app" == "Application" ]] && continue
        fp_remove+=("$app")
    done
    if [[ "${#fp_remove[@]}" -gt 0 ]]; then
        log "remove all flatpaks (${#fp_remove[@]}); next role run reinstalls"
        printf '    %s\n' "${fp_remove[@]}"
        if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
            printf 'dry-run: flatpak uninstall -y --all\n'
        elif [[ "${RESET_CONFIRM:-}" == "yes" ]]; then
            run sudo flatpak uninstall -y --all || run sudo flatpak uninstall -y "${fp_remove[@]}"
        fi
    fi
fi
