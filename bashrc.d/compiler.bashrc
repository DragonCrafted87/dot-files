#!/usr/bin/env bash
# Shared compiler defaults for interactive shells and source-build modules.
# Prefer the LLVM toolchain on OpenMandriva. Modules source this via
# load_compiler_env in setup/lib.sh so role runs match the login shell.
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
