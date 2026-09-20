#!/usr/bin/env bash
# BOINC source-build helpers: deps, compile, data-dir migrate, rpc lookup.
# Sourced from install-boinc.sh. Not a standalone role module.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

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
    # OpenMandriva names are lowercase. lib64* is the 64-bit devel;
    # the short lib*-devel name is the 32-bit compat package.
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

boinc_already_built() {
    [[ -x "${BOINC_PREFIX}/bin/boinc" ]] || return 1
    [[ -x "${BOINC_PREFIX}/bin/boincmgr" ]] || return 1
    [[ -x "${BOINC_PREFIX}/bin/boinccmd" ]] || return 1
    [[ -f "$STAMP" ]] || return 1
    [[ "$(tr -d '[:space:]' <"$STAMP")" == "$BOINC_VERSION" ]]
}

sync_boinc_source() {
    ensure_dir "$BUILD_ROOT"
    if [[ -d "${SRC_DIR}/.git" ]]; then
        log "update BOINC source in ${SRC_DIR}"
        git -C "$SRC_DIR" fetch --tags --force origin
    else
        log "clone ${BOINC_GIT_URL} -> ${SRC_DIR}"
        git clone --filter=blob:none "$BOINC_GIT_URL" "$SRC_DIR"
    fi
    local have
    have="$(git -C "$SRC_DIR" describe --tags --exact-match HEAD 2>/dev/null || true)"
    if [[ "$have" == "$BOINC_TAG" ]]; then
        log "BOINC source already at ${BOINC_TAG}"
        return 0
    fi
    log "checkout ${BOINC_TAG}"
    git -C "$SRC_DIR" checkout --detach "$BOINC_TAG"
}

build_boinc() {
    install_build_deps
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        log "would build BOINC ${BOINC_VERSION} (${BOINC_TAG}) CC=${CC:-} CFLAGS=${CFLAGS:-} in ${SRC_DIR}"
        return 0
    fi
    sync_boinc_source
    log "BOINC compilers ${CC:-cc} / ${CXX:-c++} CFLAGS=${CFLAGS:-} CXXFLAGS=${CXXFLAGS:-}"
    (
        cd "$SRC_DIR"
        ./_autosetup
        ./configure --prefix="$BOINC_PREFIX" --disable-server --disable-fcgi --disable-silent-rules --enable-unicode --with-ssl --with-x \
            CC="${CC:-clang}" CXX="${CXX:-clang++}" CFLAGS="${CFLAGS:-}" CXXFLAGS="${CXXFLAGS:-}"
        make -j"$(nproc)"
        sudo make install
    )
    sudo mkdir -p "$(dirname "$STAMP")"
    printf '%s\n' "$BOINC_VERSION" | sudo tee "$STAMP" >/dev/null
    log "installed BOINC ${BOINC_VERSION} to ${BOINC_PREFIX}"
}

remove_flatpak_boinc() {
    if command -v flatpak >/dev/null 2>&1; then
        if flatpak info edu.berkeley.BOINC >/dev/null 2>&1; then
            log "remove Flatpak edu.berkeley.BOINC"
            run sudo flatpak uninstall -y edu.berkeley.BOINC || run flatpak uninstall -y edu.berkeley.BOINC || true
        fi
    fi
    if [[ -f /etc/yum.repos.d/boinc-stable.repo ]]; then
        run sudo rm -f /etc/yum.repos.d/boinc-stable.repo
    fi
    remove_packages boinc-client boinc-manager || true
}

migrate_data_dir() {
    ensure_dir "$(dirname "$BOINC_DIR")"
    if [[ -d "$BOINC_DIR" ]]; then
        return 0
    fi
    if [[ -d "$OLD_DATA_DIR" ]]; then
        log "migrate BOINC data ${OLD_DATA_DIR} -> ${BOINC_DIR}"
        [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && return 0
        mv "$OLD_DATA_DIR" "$BOINC_DIR"
        return 0
    fi
    ensure_dir "$BOINC_DIR"
}

remove_stale_path_cmds() {
    local stale
    for stale in find-boinccmd.sh find-boinccmd boinc-session.sh boinc-session boinc-config.sh boinc-status.sh boinc-status-all.sh; do
        if [[ -e "/usr/local/bin/${stale}" ]]; then
            run sudo rm -f "/usr/local/bin/${stale}"
        fi
    done
    if [[ -e "${DOTFILES_HOME}/bin/boincmgr" ]]; then
        run rm -f "${DOTFILES_HOME}/bin/boincmgr"
    fi
}

write_config_properties() {
    local conf_dir=/etc/boinc-client
    local conf="${conf_dir}/config.properties"
    local tmp
    run sudo mkdir -p "$conf_dir"
    tmp="$(mktemp)"
    printf 'data_dir=%s\n' "$BOINC_DIR" >"$tmp"
    if [[ -f "$conf" ]] && cmp -s "$tmp" "$conf"; then
        rm -f "$tmp"
        return 0
    fi
    log "write ${conf} data_dir=${BOINC_DIR}"
    run sudo install -m 0644 "$tmp" "$conf"
    rm -f "$tmp"
}
