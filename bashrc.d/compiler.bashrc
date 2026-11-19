#!/usr/bin/env bash
# Shared compiler defaults for interactive shells and source-build modules.
# Prefer the LLVM toolchain on OpenMandriva. Modules source this via
# load_compiler_env in setup/lib/lib.sh so role runs match the login shell.
#
# Add new common flags here instead of copying them into each installer.

# /usr/bin and /sbin come before /usr/local/bin on this host, so a bare
# clang is the distro compiler. homelab-llvm installs under /usr/local.
homelab_compiler_bin() {
    local name="$1"
    if [[ -x "/usr/local/bin/${name}" ]]; then
        printf '/usr/local/bin/%s\n' "$name"
        return 0
    fi
    command -v "$name" 2>/dev/null || return 1
}

_homelab_cc="$(homelab_compiler_bin clang || true)"
_homelab_cxx="$(homelab_compiler_bin clang++ || true)"
export CC="${CC:-${_homelab_cc:-clang}}"
export CXX="${CXX:-${_homelab_cxx:-clang++}}"
export CMAKE_C_COMPILER="${CMAKE_C_COMPILER:-$CC}"
export CMAKE_CXX_COMPILER="${CMAKE_CXX_COMPILER:-$CXX}"
unset _homelab_cc _homelab_cxx

_homelab_ld="$(homelab_compiler_bin ld.lld || true)"
if [[ -n "$_homelab_ld" ]]; then
    export LD="${LD:-$_homelab_ld}"
    case " ${LDFLAGS:-} " in
        *" -fuse-ld=lld "*) ;;
        *) export LDFLAGS="${LDFLAGS:+${LDFLAGS} }-fuse-ld=lld" ;;
    esac
fi
unset _homelab_ld

_homelab_tool=""
for _homelab_tool in AR:llvm-ar RANLIB:llvm-ranlib NM:llvm-nm OBJCOPY:llvm-objcopy OBJDUMP:llvm-objdump STRIP:llvm-strip; do
    _homelab_var="${_homelab_tool%%:*}"
    _homelab_bin="$(homelab_compiler_bin "${_homelab_tool#*:}" || true)"
    if [[ -n "$_homelab_bin" && -z "${!_homelab_var:-}" ]]; then
        export "${_homelab_var}=${_homelab_bin}"
    fi
done
unset _homelab_tool _homelab_var _homelab_bin
unset -f homelab_compiler_bin

# Map -march=native to the concrete CPU the selected compiler would use
# (znver3, alderlake, ...). "native"/"mtune=native" are gcc-style
# shorthands; cmake argv splitting and some clang driver paths treat
# them as unknown flags. Leave CFLAGS/CXXFLAGS alone when already set.
# These binaries stay per-host; do not copy /usr/local between CPUs.
_dotfiles_native_cpu() {
    local cc="${1:-${CC:-clang}}"
    local dump cpu=""
    command -v "$cc" >/dev/null 2>&1 || return 1

    dump="$("$cc" -### -E -x c /dev/null -march=native 2>&1 || true)"
    # clang cc1: "-target-cpu" "znver3"
    cpu="$(printf '%s\n' "$dump" | tr '"' '\n' | awk 'tolower($0)=="-target-cpu"{getline; gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit}')"
    # gcc cc1plus: -march=znver3
    if [[ -z "$cpu" || "$cpu" == "native" ]]; then
        cpu="$(printf '%s\n' "$dump" | grep -oE -- '-march=[A-Za-z0-9._+-]+' | tail -n1 | cut -d= -f2)"
    fi
    # LLVM IR: attributes ... "target-cpu"="znver3"
    if [[ -z "$cpu" || "$cpu" == "native" ]]; then
        cpu="$(printf 'int x;\n' | "$cc" -march=native -x c -S -emit-llvm -o - - 2>/dev/null \
            | grep -oE 'target-cpu"="[^"]+' | head -n1 | cut -d'"' -f2 || true)"
    fi
    case "$cpu" in
        '' | native | generic | x86-64 | x86_64)
            return 1
            ;;
    esac
    printf '%s\n' "$cpu"
}

if [[ -z "${CFLAGS:-}" || -z "${CXXFLAGS:-}" ]]; then
    _dotfiles_cc="${CC:-clang}"
    _dotfiles_cpu=""
    if command -v "$_dotfiles_cc" >/dev/null 2>&1; then
        _dotfiles_cpu="$(_dotfiles_native_cpu "$_dotfiles_cc" || true)"
    fi
    if [[ -n "$_dotfiles_cpu" ]]; then
        _dotfiles_native="-O2 -pipe -march=${_dotfiles_cpu}"
    else
        _dotfiles_native="-O2 -pipe"
    fi
    export CFLAGS="${CFLAGS:-${_dotfiles_native}}"
    export CXXFLAGS="${CXXFLAGS:-${_dotfiles_native}}"
    unset _dotfiles_native _dotfiles_cpu _dotfiles_cc
fi

if [[ -z "${MAKEFLAGS:-}" ]]; then
    export MAKEFLAGS="-j$(nproc)"
fi
