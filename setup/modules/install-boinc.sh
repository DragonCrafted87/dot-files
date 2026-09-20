#!/usr/bin/env bash
# Build BOINC client + manager from the tagged GitHub source.
# OpenMandriva has no working BOINC rpms; Fedora packages ABI-mismatch.
# Version comes from setup/versions.conf so a role rerun skips the compile
# when the stamp matches.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/files/boinc/manager-setup.sh"

require_user

BOINC_VERSION="${BOINC_VERSION:?set BOINC_VERSION in setup/versions.conf}"
BOINC_TAG="${BOINC_TAG:-client_release/8.2/${BOINC_VERSION}}"
BOINC_GIT_URL="${BOINC_GIT_URL:-https://github.com/BOINC/boinc.git}"
BOINC_PREFIX="${BOINC_PREFIX:-/usr/local}"
STAMP="${BOINC_PREFIX}/share/boinc/.dotfiles-version"
BUILD_ROOT="${DOTFILES_HOME}/.cache/boinc-build"
SRC_DIR="${BUILD_ROOT}/boinc"
OLD_DATA_DIR="${DOTFILES_HOME}/.var/app/edu.berkeley.BOINC"
BOINC_DIR="${DOTFILES_HOME}/.local/share/boinc"
