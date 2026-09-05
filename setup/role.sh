#!/usr/bin/env bash
# Apply or reset a machine role. Module lists live in roles.conf.
#
#   ./setup/role.sh workstation
#   ./setup/role.sh --reset laptop
#   ./setup/role.sh --reset --force server
#   ./setup/role.sh --dry-run --reset htpc
#   ./setup/role.sh --hostname study.lan laptop

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
    cat >&2 <<EOF
usage: $0 [options] <role>

Roles: workstation, laptop, htpc, server

Options:
  --reset              re-apply the role, then list extra packages
  --force              with --reset, actually remove the extras
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
ensure_hostname "${hostname_arg}"
record_role "$role"

if [[ "$do_reset" -eq 1 ]]; then
    log "re-apply ${role} so declared packages are present"
fi

while IFS= read -r module; do
    [[ -n "$module" ]] || continue
    run_module "$module"
done < <(role_modules "$role")

if [[ "$do_reset" -eq 1 ]]; then
    log "remove extras that are not part of ${role}"
    OMV_ROLE="$role" bash "${SETUP_DIR}/modules/prune-extra-packages.sh"
    run_module remove-plasma-sddm

    log "reset of ${role} finished"
    log "home files were left in place"
    if [[ "$force" -ne 1 && "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
        log "review the extras list, then rerun with --reset --force to actually remove them"
    fi
fi
