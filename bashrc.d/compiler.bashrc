#!/usr/bin/env bash
# Shared compiler defaults for interactive shells and source-build modules.
# Prefer the LLVM toolchain on OpenMandriva. Modules source this via
# load_compiler_env in setup/lib/lib.sh so role runs match the login shell.
#
# Add new common flags here instead of copying them into each installer.

export CC="${CC:-clang}"
export CXX="${CXX:-clang++}"
export CMAKE_C_COMPILER="${CMAKE_C_COMPILER:-clang}"
export CMAKE_CXX_COMPILER="${CMAKE_CXX_COMPILER:-clang++}"

if command -v ld.lld >/dev/null 2>&1; then
    export LD="${LD:-ld.lld}"
    case " ${LDFLAGS:-} " in
        *" -fuse-ld=lld "*) ;;
        *) export LDFLAGS="${LDFLAGS:+${LDFLAGS} }-fuse-ld=lld" ;;
    esac
fi

command -v llvm-ar >/dev/null 2>&1 && export AR="${AR:-llvm-ar}"
command -v llvm-ranlib >/dev/null 2>&1 && export RANLIB="${RANLIB:-llvm-ranlib}"
command -v llvm-nm >/dev/null 2>&1 && export NM="${NM:-llvm-nm}"
command -v llvm-objcopy >/dev/null 2>&1 && export OBJCOPY="${OBJCOPY:-llvm-objcopy}"
command -v llvm-objdump >/dev/null 2>&1 && export OBJDUMP="${OBJDUMP:-llvm-objdump}"
command -v llvm-strip >/dev/null 2>&1 && export STRIP="${STRIP:-llvm-strip}"

# Tune to this machine. clang -march=native maps AMD family 23+ to
# znver1/znver2/znver3/znver4/znver5 from CPUID. Do not hard-code
# -march=znver1: that freezes later Zen chips at the first-gen ISA.
# Leave CFLAGS/CXXFLAGS alone when the caller already set them.
# These binaries stay per-host; do not copy /usr/local between CPUs.
if [[ -z "${CFLAGS:-}" || -z "${CXXFLAGS:-}" ]]; then
    _dotfiles_cc="${CC:-clang}"
    if command -v "$_dotfiles_cc" >/dev/null 2>&1 \
        && "$_dotfiles_cc" -march=native -E -x c /dev/null >/dev/null 2>&1; then
        _dotfiles_native="-O2 -pipe -march=native -mtune=native"
        export CFLAGS="${CFLAGS:-${_dotfiles_native}}"
        export CXXFLAGS="${CXXFLAGS:-${_dotfiles_native}}"
        unset _dotfiles_native
    fi
    unset _dotfiles_cc
fi

if [[ -z "${MAKEFLAGS:-}" ]]; then
    export MAKEFLAGS="-j$(nproc)"
fi
