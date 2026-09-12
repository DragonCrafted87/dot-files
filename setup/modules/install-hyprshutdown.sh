#!/usr/bin/env bash
# Graceful Hyprland logout/reboot helper. Prefer the distro package.
# If it is missing, build upstream with clang/lld like MakeMKV.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

HYPRSHUTDOWN_REPO="${HYPRSHUTDOWN_REPO:-https://github.com/hyprwm/hyprshutdown.git}"
HYPRSHUTDOWN_SRC="${HYPRSHUTDOWN_SRC:-${DOTFILES_HOME}/.cache/hyprshutdown-src}"
HYPRSHUTDOWN_PREFIX="${HYPRSHUTDOWN_PREFIX:-/usr/local}"
STAMP="${HYPRSHUTDOWN_PREFIX}/share/hyprshutdown/.dotfiles-revision"

pick_pkg() {
    local p
    for p in "$@"; do
        if rpm -q "$p" >/dev/null 2>&1; then
            printf '%s\n' "$p"
            return 0
        fi
        if dnf list --available "$p" >/dev/null 2>&1; then
            printf '%s\n' "$p"
            return 0
        fi
    done
    return 1
}

if command -v hyprshutdown >/dev/null 2>&1 && [[ "${HYPRSHUTDOWN_FORCE_BUILD:-0}" != "1" ]]; then
    log "hyprshutdown already on PATH: $(command -v hyprshutdown)"
    exit 0
fi

if [[ "${HYPRSHUTDOWN_FORCE_BUILD:-0}" != "1" ]] && dnf list --available hyprshutdown >/dev/null 2>&1; then
    ensure_packages hyprshutdown
    if command -v hyprshutdown >/dev/null 2>&1; then
        log "installed hyprshutdown from dnf"
        exit 0
    fi
    warn "hyprshutdown rpm installed but not on PATH; building from source"
fi

install_build_deps() {
    local pkgs=() picked group
    local groups=(
        "clang"
        "llvm"
        "lld"
        "cmake"
        "make"
        "git"
        "pkgconf pkgconfig"
        "hyprtoolkit"
        "hyprutils"
        "hyprtoolkit-devel lib64hyprtoolkit-devel"
        "hyprutils-devel lib64hyprutils-devel"
        "pixman-devel lib64pixman-devel lib64pixman1-devel"
        "libdrm-devel lib64drm-devel lib64drm2-devel"
        "glaze-devel lib64glaze-devel glaze"
    )
    for group in "${groups[@]}"; do
        # shellcheck disable=SC2086
        if picked="$(pick_pkg $group)"; then
            pkgs+=("$picked")
        fi
    done
    [[ "${#pkgs[@]}" -gt 0 ]] && ensure_packages "${pkgs[@]}"
}

install_build_deps
command -v clang >/dev/null 2>&1 || die "clang is not on PATH after package install"
command -v clang++ >/dev/null 2>&1 || die "clang++ is not on PATH after package install"
command -v cmake >/dev/null 2>&1 || die "cmake is not on PATH after package install"

ensure_repo "$HYPRSHUTDOWN_REPO" "$HYPRSHUTDOWN_SRC"

rev="$(git -C "$HYPRSHUTDOWN_SRC" rev-parse HEAD)"
if [[ -x "${HYPRSHUTDOWN_PREFIX}/bin/hyprshutdown" && -f "$STAMP" ]] \
    && [[ "$(cat "$STAMP")" == "$rev" ]]; then
    log "hyprshutdown ${rev} already built at ${HYPRSHUTDOWN_PREFIX}/bin/hyprshutdown"
    exit 0
fi

if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
    log "would build hyprshutdown ${rev} with clang in ${HYPRSHUTDOWN_SRC}/build"
    exit 0
fi

export CC=clang
export CXX=clang++
export CMAKE_C_COMPILER=clang
export CMAKE_CXX_COMPILER=clang++
if command -v ld.lld >/dev/null 2>&1; then
    export LDFLAGS="${LDFLAGS:-} -fuse-ld=lld"
fi

cmake -S "$HYPRSHUTDOWN_SRC" -B "${HYPRSHUTDOWN_SRC}/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_INSTALL_PREFIX="$HYPRSHUTDOWN_PREFIX"
cmake --build "${HYPRSHUTDOWN_SRC}/build" -j"$(nproc)"
sudo cmake --install "${HYPRSHUTDOWN_SRC}/build"
sudo mkdir -p "$(dirname "$STAMP")"
printf '%s\n' "$rev" | sudo tee "$STAMP" >/dev/null
log "installed hyprshutdown ${rev} with clang to ${HYPRSHUTDOWN_PREFIX}/bin/hyprshutdown"
