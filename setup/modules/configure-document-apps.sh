#!/usr/bin/env bash
# Deprecated. Split into install-office-printing (LibreOffice / Okular),
# install-gaming-packages (MultiMC), and configure-mime-defaults (Tango
# icons). Brave chrome is not themed from this repo. Kept so an old
# roles.conf line does not die.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user
log "configure-document-apps is split; nothing to do"
