#!/usr/bin/env bash
# Build BOINC client + manager from the tagged GitHub source.
# OpenMandriva has no working BOINC rpms; Fedora packages ABI-mismatch.
# Version comes from setup/versions.conf so a role rerun skips the compile
# when the stamp matches.
#
# Split helpers live next to this file:
#   install-boinc-defs.sh      build/install functions
#   install-boinc-run.sh       data dir, prefs, units, PATH helpers
#   install-boinc-manager.sh   manager desktop + ComputerMRU

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib.sh"

require_user

# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install-boinc-defs.sh"
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install-boinc-manager.sh"
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install-boinc-run.sh"
