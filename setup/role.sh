#!/usr/bin/env bash
# Apply or reset a machine role. Module lists live in roles.conf.
#
#   ./setup/role.sh workstation
#   ./setup/role.sh --enable-subrole laptop
#   ./setup/role.sh --reset workstation
#   ./setup/role.sh --reset --force workstation
#
# --reset strips toward the ISO-minus-strip baseline. It does not re-run
# modules. After a forced reset, run role.sh again without --reset.
# --reset --force must be a real VT (Ctrl+Alt+F3) or SSH, not
# Ly/Hyprland/Plasma. A bare --reset only lists extras and may run
# from a graphical session.
#
# Subroles are saved in ~/.config/dot-files/subroles and re-applied on
# every later role run. They are not derived from the hostname.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/subroles.sh"

usage() {
    cat >&2 <<EOF
usage: $0 [options] [role]

Roles: workstation, htpc, server
       laptop is a subrole: --enable-subrole laptop

Subroles: $(known_subroles | paste -sd, -)

Options:
  --enable-subrole NAME    save NAME and apply its modules
  --disable-subrole NAME   drop NAME from the saved list
  --list-subroles          print known and enabled subroles
  --reset                  list packages that a force-reset would remove
  --force                  with --reset, actually strip to the ISO baseline
  --dry-run                print actions without changing the system
  --hostname NAME          set the static hostname
  -h, --help               show this help
EOF
    exit 1
}

role=""
cli_role=0
do_reset=0
force=0
list_subroles=0
hostname_arg=""
enable_subroles=()
disable_subroles=()

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --reset | -r)
            do_reset=1
            ;;
        --force | -f)
            force=1
            ;;
        --dry-run)
            DOTFILES_DRY_RUN=1
            export DOTFILES_DRY_RUN
            ;;
        --hostname)
            [[ "$#" -ge 2 ]] || usage
            hostname_arg="$2"
            shift
            ;;
        --hostname=*)
            hostname_arg="${1#--hostname=}"
            ;;
        --enable-subrole)
            [[ "$#" -ge 2 ]] || usage
            enable_subroles+=("$2")
            shift
            ;;
        --enable-subrole=*)
            enable_subroles+=("${1#--enable-subrole=}")
            ;;
        --disable-subrole)
            [[ "$#" -ge 2 ]] || usage
            disable_subroles+=("$2")
            shift
            ;;
        --disable-subrole=*)
            disable_subroles+=("${1#--disable-subrole=}")
            ;;
        --list-subroles)
            list_subroles=1
            ;;
        -h | --help)
            usage
            ;;
        --)
            shift
            break
            ;;
        -*)
            printf 'error: unknown option %s\n' "$1" >&2
            usage
            ;;
        *)
            if [[ -n "$role" ]]; then
                usage
            fi
            role="$1"
            cli_role=1
            ;;
    esac
    shift
done

require_user

if [[ "$list_subroles" -eq 1 ]]; then
    log "known subroles"
    known_subroles
    log "enabled subroles ($(subroles_file))"
    if [[ -z "$(read_saved_subroles)" ]]; then
        printf '(none)\n'
    else
        read_saved_subroles
    fi
    exit 0
fi

if [[ "$force" -eq 1 && "$do_reset" -eq 0 ]]; then
    die "--force is only used with --reset"
fi

if [[ "$force" -eq 1 ]]; then
    RESET_CONFIRM=yes
    export RESET_CONFIRM
else
    RESET_CONFIRM=""
    export RESET_CONFIRM
fi

if ! command -v git >/dev/null 2>&1; then
    log "bootstrap git (missing on this root)"
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        printf 'dry-run: sudo dnf install -y git\n'
    else
        sudo dnf install -y git
        command -v git >/dev/null 2>&1 || die "git is still missing after dnf install"
    fi
fi

ensure_hostname "${hostname_arg}"

if [[ "$role" == "laptop" ]]; then
    die "laptop is a subrole; run: $0 workstation --enable-subrole laptop"
fi
if [[ -z "$role" ]]; then
    role="$(read_saved_role || true)"
fi
if [[ "$role" == "laptop" ]]; then
    die "saved role is laptop; write workstation to ~/.config/dot-files/role and enable-subrole laptop"
fi
[[ -n "$role" ]] || die "no role saved; pass workstation, htpc, or server once"
valid_role "$role" || die "unknown role ${role}"

for name in "${enable_subroles[@]}"; do
    enable_saved_subrole "$name"
done
for name in "${disable_subroles[@]}"; do
    if ! valid_subrole "$name" && ! has_subrole "$name"; then
        die "unknown subrole ${name}"
    fi
    disable_saved_subrole "$name"
done

record_role "$role"
load_subroles_env

if [[ "$do_reset" -eq 1 ]]; then
    log "strip toward ISO baseline (role packages come back on the next plain run)"
    OMV_ROLE="$role" bash "${SETUP_DIR}/modules/prune-extra-packages.sh"
    if [[ "$force" -eq 1 && "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
        log "baseline strip finished. home files were left in place."
        log "log in on a VT or SSH and run: $0 ${role}"
    elif [[ "$force" -ne 1 && "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
        log "review the extras list, then from a VT or SSH: $0 --reset --force ${role}"
    fi
    exit 0
fi

run_full=1
if [[ "$cli_role" -eq 0 && ("${#enable_subroles[@]}" -gt 0 || "${#disable_subroles[@]}" -gt 0) ]]; then
    run_full=0
fi

if [[ "$run_full" -eq 1 ]]; then
    while IFS= read -r module; do
        [[ -n "$module" ]] || continue
        run_module "$module"
    done < <(role_modules "$role")
else
    for name in "${enable_subroles[@]}"; do
        while IFS= read -r module; do
            [[ -n "$module" ]] || continue
            run_module "$module"
        done < <(subrole_modules "$name")
    done
    if [[ "${#disable_subroles[@]}" -gt 0 && "${#enable_subroles[@]}" -eq 0 ]]; then
        log "disabled subroles: ${disable_subroles[*]}"
        log "packages already installed are left in place; next update-role skips those modules"
    fi
fi

restart_qs_if_needed
