#!/usr/bin/env bash
# Build MakeMKV with a working C toolchain, enable Ask for single drive
# mode, and install one Desktop launcher. Skip the whole module when this
# machine has no DVD/Blu-ray device.
#
# Fresh Rock installs often have clang on PATH that fails autoconf's
# AC_PROG_CC ("invalid C compiler") because gcc/glibc-devel are missing.
# Prefer gcc/g++ when they compile a trivial file; fall back to clang.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

MAKEMKV_VERSION="${MAKEMKV_VERSION:-1.18.4}"
MAKEMKV_PREFIX="${MAKEMKV_PREFIX:-/usr}"
STAMP="${MAKEMKV_PREFIX}/share/makemkv/.dotfiles-version"
BUILD_ROOT="${DOTFILES_HOME}/.cache/makemkv-build"
OSS_URL="https://www.makemkv.com/download/makemkv-oss-${MAKEMKV_VERSION}.tar.gz"
BIN_URL="https://www.makemkv.com/download/makemkv-bin-${MAKEMKV_VERSION}.tar.gz"

optical_drives() {
    local node real seen=""
    shopt -s nullglob
    for node in /dev/sr[0-9]* /dev/cdrom /dev/dvd /dev/bd /dev/bluray; do
        [[ -b "$node" || -L "$node" ]] || continue
        real="$(readlink -f "$node" 2>/dev/null || printf '%s' "$node")"
        [[ -b "$real" ]] || continue
        case " $seen " in
            *" $real "*) continue ;;
        esac
        if command -v udevadm >/dev/null 2>&1; then
            if ! udevadm info --query=property --name="$real" 2>/dev/null \
                | grep -q '^ID_CDROM=1$'; then
                continue
            fi
        fi
        printf '%s\n' "$real"
        seen="$seen $real"
    done
}

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

install_build_deps() {
    local pkgs=()
    local picked
    local group
    local groups=(
        "gcc"
        "gcc-c++ gcc-c++-x86_64 gcc-c++-znver1"
        "glibc-devel lib64c-devel"
        "libstdc++-devel lib64stdc++-devel"
        "binutils"
        "clang"
        "llvm"
        "lld"
        "make"
        "pkgconf pkgconfig"
        "wget"
        "openssl-devel lib64openssl-devel"
        "expat-devel lib64expat-devel lib64expat1-devel"
        "zlib-devel lib64zlib-devel"
        "lib64ffmpeg-devel libffmpeg-devel ffmpeg-devel"
        "qt5-qtbase-devel lib64qt5core-devel qt5-devel"
        "lib64mesagl-devel mesa-libGL-devel lib64mesaegl-devel"
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

compiler_works() {
    local cc="$1"
    local tmp src obj
    command -v "$cc" >/dev/null 2>&1 || return 1
    tmp="$(mktemp -d)"
    src="${tmp}/t.c"
    obj="${tmp}/t"
    printf 'int main(void){return 0;}\n' >"$src"
    if "$cc" -o "$obj" "$src" >/dev/null 2>&1; then
        rm -rf "$tmp"
        return 0
    fi
    rm -rf "$tmp"
    return 1
}

pick_compilers() {
    if compiler_works clang && command -v clang++ >/dev/null 2>&1; then
        printf '%s %s\n' clang clang++
        return 0
    fi
    if compiler_works gcc && command -v g++ >/dev/null 2>&1; then
        printf '%s %s\n' gcc g++
        return 0
    fi
    return 1
}

accept_eula() {
    mkdir -p tmp
    printf 'accepted\n' >tmp/eula_accepted
}

drives="$(optical_drives || true)"
if [[ -z "$drives" ]]; then
    log "no DVD/Blu-ray drive attached; skip MakeMKV"
    exit 0
fi
log "optical drives: $(printf '%s' "$drives" | tr '\n' ' ')"

if getent group cdrom >/dev/null 2>&1; then
    if ! id -nG "$DOTFILES_USER" | grep -qw cdrom; then
        log "add ${DOTFILES_USER} to cdrom"
        run sudo usermod -aG cdrom "$DOTFILES_USER"
    fi
fi

if [[ -x "${MAKEMKV_PREFIX}/bin/makemkv" && -f "$STAMP" ]] \
    && [[ "$(cat "$STAMP")" == "$MAKEMKV_VERSION" ]]; then
    log "MakeMKV ${MAKEMKV_VERSION} already installed"
else
    install_build_deps
    local_cc=""
    local_cxx=""
    if read -r local_cc local_cxx < <(pick_compilers); then
        log "MakeMKV compilers ${local_cc} / ${local_cxx}"
    else
        die "no working C compiler after package install (gcc and clang both failed a trivial compile)"
    fi

    ensure_dir "$BUILD_ROOT"
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        log "would build MakeMKV ${MAKEMKV_VERSION} with ${local_cc} in ${BUILD_ROOT}"
    else
        export CC="$local_cc"
        export CXX="$local_cxx"
        export OBJCOPY="${OBJCOPY:-objcopy}"
        if command -v llvm-objcopy >/dev/null 2>&1 && [[ "$local_cc" == clang ]]; then
            export OBJCOPY=llvm-objcopy
        fi
        if command -v ld.lld >/dev/null 2>&1 && [[ "$local_cc" == clang ]]; then
            export LDFLAGS="${LDFLAGS:-} -fuse-ld=lld"
        fi

        run wget -q -O "${BUILD_ROOT}/makemkv-oss.tar.gz" "$OSS_URL"
        run wget -q -O "${BUILD_ROOT}/makemkv-bin.tar.gz" "$BIN_URL"
        run rm -rf "${BUILD_ROOT}/makemkv-oss-${MAKEMKV_VERSION}" \
            "${BUILD_ROOT}/makemkv-bin-${MAKEMKV_VERSION}"
        run tar -xzf "${BUILD_ROOT}/makemkv-oss.tar.gz" -C "$BUILD_ROOT"
        run tar -xzf "${BUILD_ROOT}/makemkv-bin.tar.gz" -C "$BUILD_ROOT"

        (
            cd "${BUILD_ROOT}/makemkv-oss-${MAKEMKV_VERSION}"
            ./configure --prefix="$MAKEMKV_PREFIX" CC="$CC" CXX="$CXX"
            make -j"$(nproc)"
            sudo make install
        )
        (
            cd "${BUILD_ROOT}/makemkv-bin-${MAKEMKV_VERSION}"
            accept_eula
            make -j"$(nproc)"
            sudo make install
        )
        sudo mkdir -p "$(dirname "$STAMP")"
        printf '%s\n' "$MAKEMKV_VERSION" | sudo tee "$STAMP" >/dev/null
        log "installed MakeMKV ${MAKEMKV_VERSION} with ${local_cc}"
    fi
fi

sync_src="${SETUP_FILES_DIR}/makemkv/sync-makemkv-desktops.sh"
[[ -f "$sync_src" ]] || die "missing ${sync_src}"

ensure_dir "${DOTFILES_HOME}/bin"
run install -m 0755 "$sync_src" "${DOTFILES_HOME}/bin/sync-makemkv-desktops.sh"

if [[ -f "${DOTFILES_HOME}/.config/autostart/makemkv-sync-desktops.desktop" ]]; then
    run rm -f "${DOTFILES_HOME}/.config/autostart/makemkv-sync-desktops.desktop"
fi

if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
    "${DOTFILES_HOME}/bin/sync-makemkv-desktops.sh"
fi
