#!/usr/bin/env bash
# Keep files, restore the role's package set, drop experimental extras.
# Does not reinstall the OS or touch /home except what the role already links.
#
#   ./setup/openmandriva/reset-to-role.sh workstation
#   DOTFILES_DRY_RUN=1 ./setup/openmandriva/reset-to-role.sh laptop
#   RESET_CONFIRM=yes ./setup/openmandriva/reset-to-role.sh server

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${here}/lib.sh"

role="${1:-${OMV_ROLE:-}}"
if [[ -z "$role" ]]; then
    printf 'usage: %s workstation|laptop|htpc|server\n' "$0" >&2
    exit 1
fi

case "$role" in
    workstation | laptop | htpc | server) ;;
    *)
        die "unknown role ${role}"
        ;;
esac

require_user
record_role "$role"

log "re-apply ${role} so declared packages are present"
"${here}/${role}.sh"

log "remove extras that are not part of ${role}"
RESET_CONFIRM="${RESET_CONFIRM:-}" OMV_ROLE="$role" \
    bash "${here}/modules/prune-extra-packages.sh"
run_module remove-plasma-sddm

log "reset of ${role} finished"
log "home files were left in place"
if [[ "${RESET_CONFIRM:-}" != "yes" && "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
    log "review the extras list, then rerun with RESET_CONFIRM=yes to actually remove them"
fi
