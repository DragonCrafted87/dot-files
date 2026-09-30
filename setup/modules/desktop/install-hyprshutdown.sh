#!/usr/bin/env bash
# hyprshutdown is built by install-hyprland-source into /usr/local.
# Do not install the distro hyprshutdown / hyprutils / hyprtoolkit rpms;
# those put Rock libhyprutils back on the linker path.

set -euo pipefail
# shellcheck disable=SC1091
. "${REPO_ROOT:-$DOTFILES_ROOT}/setup/lib/lib.sh"

require_user

bin="${HYPRLAND_SOURCE_PREFIX:-/usr/local}/bin/hyprshutdown"
if [[ -x "$bin" ]]; then
    log "hyprshutdown: ${bin}"
    exit 0
fi
log "hyprshutdown: ${bin} is not installed yet; install-hyprland-source builds it"
exit 0
