#!/usr/bin/env bash
# Build BOINC client + manager from the tagged GitHub source.
set -euo pipefail
SETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
. "${SETUP_ROOT}/lib.sh"
require_user
# shellcheck disable=SC1091
. "${SETUP_ROOT}/files/boinc/manager-setup.sh"
# shellcheck disable=SC1091
. "${SETUP_ROOT}/files/boinc/install-boinc-defs.sh"
# shellcheck disable=SC1091
. "${SETUP_ROOT}/files/boinc/install-boinc-run.sh"
