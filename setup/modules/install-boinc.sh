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

install_build_deps() {
    local pkgs=()
    local picked group
    local groups=(
        "git" "clang" "llvm" "lld" "gcc"
        "gcc-c++ gcc-c++-znver1 gcc-c++-x86_64"
        "glibc-devel lib64c-devel"
        "lib64stdc++-devel libstdc++-devel"
        "make" "autoconf" "automake" "libtool" "pkgconf pkgconfig" "m4"
        "lib64openssl-devel openssl-devel"
        "lib64curl-devel libcurl-devel curl-devel"
        "lib64z-devel zlib-devel"
        "lib64sqlite3-devel sqlite-devel"
        "lib64notify-devel libnotify-devel"
        "lib64x11-devel libx11-devel"
        "lib64xmu-devel libxmu-devel"
        "lib64xscrnsaver-devel libxscrnsaver-devel"
        "lib64freeglut-devel freeglut-devel"
        "lib64glu-devel mesa-libglu-devel"
        "lib64jpeg-devel libjpeg-devel libjpeg-turbo-devel"
        "lib64xcb-util-devel xcb-util-devel"
        "lib64gtk+3.0-devel libgtk+3.0-devel"
        "lib64wxgtku3.2-devel lib64wxgtku3.0-devel lib64wxu3.2-devel"
        "gettext"
    )
    for group in "${groups[@]}"; do
        # shellcheck disable=SC2086
        if picked="$(pick_pkg $group)"; then
            pkgs+=("$picked")
        else
            warn "no package matched: $group"
        fi
    done
    ensure_packages "${pkgs[@]}"
}
