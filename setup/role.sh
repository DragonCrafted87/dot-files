#!/usr/bin/env bash
# Apply or reset a machine role.
#
#   ./setup/role.sh workstation
#   ./setup/role.sh laptop reset
#   RESET_CONFIRM=yes ./setup/role.sh server reset
#   DOTFILES_DRY_RUN=1 ./setup/role.sh htpc
#   DOTFILES_HOSTNAME=study.lan ./setup/role.sh laptop

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
    printf 'usage: %s workstation|laptop|htpc|server [reset]\n' "$0" >&2
    exit 1
}

role=""
do_reset=0
for arg in "$@"; do
    case "$arg" in
        reset | --reset | -r)
            do_reset=1
            ;;
        -h | --help)
            usage
            ;;
        *)
            if [[ -n "$role" ]]; then
                usage
            fi
            role="$arg"
            ;;
    esac
done

if [[ -z "$role" ]]; then
    role="${OMV_ROLE:-}"
fi
[[ -n "$role" ]] || usage
valid_role "$role" || die "unknown role ${role}"

require_user
ensure_hostname "${DOTFILES_HOSTNAME:-}"
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
    RESET_CONFIRM="${RESET_CONFIRM:-}" OMV_ROLE="$role" \
        bash "${SETUP_DIR}/modules/prune-extra-packages.sh"
    run_module remove-plasma-sddm

    log "reset of ${role} finished"
    log "home files were left in place"
    if [[ "${RESET_CONFIRM:-}" != "yes" && "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
        log "review the extras list, then rerun with RESET_CONFIRM=yes to actually remove them"
    fi
fi
