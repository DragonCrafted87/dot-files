#!/usr/bin/env bash
# Graceful Hyprland logout/reboot helper. Prefer the distro package.
# Build upstream with clang only when the packaged Hypr stack is new enough.
# Current Rock/OMV hyprutils is 0.6 and has no hyprtoolkit; session-control.sh
# already falls back to hyprctl dispatch exit in that case.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

HYPRSHUTDOWN_REPO="${HYPRSHUTDOWN_REPO:-https://github.com/hyprwm/hyprshutdown.git}"
HYPRSHUTDOWN_SRC="${HYPRSHUTDOWN_SRC:-${DOTFILES_HOME}/.cache/hyprshutdown-src}"
HYPRSHUTDOWN_PREFIX="${HYPRSHUTDOWN_PREFIX:-/usr/local}"
STAMP="${HYPRSHUTDOWN_PREFIX}/share/hyprshutdown/.dotfiles-revision"
NEED_HYPRUTILS="${HYPRSHUTDOWN_MIN_HYPRUTILS:-0.11.0}"

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

pc_mod() {
    command -v pkg-config >/dev/null 2>&1 || return 1
    pkg-config "$@"
}

stack_ready_to_build() {
    pc_mod --exists hyprtoolkit || return 1
    pc_mod --atleast-version="$NEED_HYPRUTILS" hyprutils || return 1
    pc_mod --exists pixman-1 || return 1
    pc_mod --exists libdrm || return 1
    return 0
}

explain_missing_stack() {
    local hu="none" ht="missing"
    if pc_mod --exists hyprutils; then
        hu="$(pc_mod --modversion hyprutils)"
    fi
    if pc_mod --exists hyprtoolkit; then
        ht="$(pc_mod --modversion hyprtoolkit)"
    fi
    warn "hyprshutdown source needs hyprtoolkit and hyprutils >= ${NEED_HYPRUTILS}"
    warn "this host has hyprtoolkit=${ht} hyprutils=${hu}"
    warn "leaving logout on hyprctl dispatch exit until the distro Hypr stack catches up"
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
    warn "hyprshutdown rpm installed but not on PATH"
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

if ! stack_ready_to_build; then
    explain_missing_stack
    exit 0
fi

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
