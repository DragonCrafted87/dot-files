#!/usr/bin/env bash
# Apply or reset a machine role. Module lists live in roles.conf.
#
#   ./setup/role.sh workstation
#   ./setup/role.sh --reset workstation
#   ./setup/role.sh --reset --force workstation
#
# --reset strips toward the ISO-minus-strip baseline. It does not re-run
# modules. After a forced reset, run role.sh again without --reset.
# --reset must be a real VT (Ctrl+Alt+F3) or SSH, not Ly/Hyprland/Plasma.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
    cat >&2 <<EOF
usage: $0 [options] <role>

Roles: workstation, laptop, htpc, server

Options:
  --reset              list packages that a force-reset would remove
  --force              with --reset, actually strip to the ISO baseline
  --dry-run            print actions without changing the system
  --hostname NAME      set the static hostname
  -h, --help           show this help
EOF
    exit 1
}

role=""
do_reset=0
force=0
hostname_arg=""

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
            ;;
    esac
    shift
done

[[ -n "$role" ]] || usage
valid_role "$role" || die "unknown role ${role}"

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

require_user

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
record_role "$role"

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

while IFS= read -r module; do
    [[ -n "$module" ]] || continue
    run_module "$module"
done < <(role_modules "$role")

restart_qs_if_needed
