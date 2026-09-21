#!/usr/bin/env bash
# Build the pinned Hyprland tag plus the hypr* ecosystem into an isolated prefix.
# Tags live in setup/versions.conf. This prefix is linked against libc++.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

HYPRLAND_TAG="${HYPRLAND_TAG:?set HYPRLAND_TAG in setup/versions.conf}"
HYPRLAND_SOURCE_VERSION="${HYPRLAND_SOURCE_VERSION:-${HYPRLAND_TAG#v}}"
PREFIX="${HYPRLAND_SOURCE_PREFIX:-/opt/hyprland-${HYPRLAND_SOURCE_VERSION}}"
TEMPLATE_PREFIX="/opt/hyprland-0.56.2"
SRC_ROOT="${HYPRLAND_SOURCE_SRC:-${DOTFILES_HOME}/.cache/hyprland-source}"
STAMP="${PREFIX}/share/hyprland-source/.dotfiles-stamp"
SESSION_DESKTOP_SRC="${SETUP_FILES_DIR}/hyprland-source/hyprland-source.desktop"
SESSION_WRAPPER_SRC="${SETUP_FILES_DIR}/hyprland-source/start-hyprland-source.sh"
LY_CUSTOM_DIR="/etc/ly/custom-sessions"
WAYLAND_SESSION_DIR="/usr/share/wayland-sessions"

AQUAMARINE_TAG="${AQUAMARINE_TAG:?set AQUAMARINE_TAG in setup/versions.conf}"
HYPRCURSOR_TAG="${HYPRCURSOR_TAG:?set HYPRCURSOR_TAG in setup/versions.conf}"
HYPRGRAPHICS_TAG="${HYPRGRAPHICS_TAG:?set HYPRGRAPHICS_TAG in setup/versions.conf}"
HYPRIDLE_TAG="${HYPRIDLE_TAG:?set HYPRIDLE_TAG in setup/versions.conf}"
HYPRLAND_GUIUTILS_TAG="${HYPRLAND_GUIUTILS_TAG:?set HYPRLAND_GUIUTILS_TAG in setup/versions.conf}"
HYPRLAND_PROTOCOLS_TAG="${HYPRLAND_PROTOCOLS_TAG:?set HYPRLAND_PROTOCOLS_TAG in setup/versions.conf}"
HYPRLAND_QT_SUPPORT_TAG="${HYPRLAND_QT_SUPPORT_TAG:?set HYPRLAND_QT_SUPPORT_TAG in setup/versions.conf}"
HYPRLANG_TAG="${HYPRLANG_TAG:?set HYPRLANG_TAG in setup/versions.conf}"
HYPRLAUNCHER_TAG="${HYPRLAUNCHER_TAG:?set HYPRLAUNCHER_TAG in setup/versions.conf}"
HYPRLOCK_TAG="${HYPRLOCK_TAG:?set HYPRLOCK_TAG in setup/versions.conf}"
HYPRPAPER_TAG="${HYPRPAPER_TAG:?set HYPRPAPER_TAG in setup/versions.conf}"
HYPRPICKER_TAG="${HYPRPICKER_TAG:?set HYPRPICKER_TAG in setup/versions.conf}"
HYPRPOLKITAGENT_TAG="${HYPRPOLKITAGENT_TAG:?set HYPRPOLKITAGENT_TAG in setup/versions.conf}"
HYPRPWCENTER_TAG="${HYPRPWCENTER_TAG:?set HYPRPWCENTER_TAG in setup/versions.conf}"
HYPRQT6ENGINE_TAG="${HYPRQT6ENGINE_TAG:?set HYPRQT6ENGINE_TAG in setup/versions.conf}"
HYPRSHUTDOWN_TAG="${HYPRSHUTDOWN_TAG:?set HYPRSHUTDOWN_TAG in setup/versions.conf}"
HYPRSUNSET_TAG="${HYPRSUNSET_TAG:?set HYPRSUNSET_TAG in setup/versions.conf}"
HYPRSYSTEMINFO_TAG="${HYPRSYSTEMINFO_TAG:?set HYPRSYSTEMINFO_TAG in setup/versions.conf}"
HYPRTOOLKIT_TAG="${HYPRTOOLKIT_TAG:?set HYPRTOOLKIT_TAG in setup/versions.conf}"
HYPRUTILS_TAG="${HYPRUTILS_TAG:?set HYPRUTILS_TAG in setup/versions.conf}"
HYPRWAYLAND_SCANNER_TAG="${HYPRWAYLAND_SCANNER_TAG:?set HYPRWAYLAND_SCANNER_TAG in setup/versions.conf}"
HYPRWIRE_TAG="${HYPRWIRE_TAG:?set HYPRWIRE_TAG in setup/versions.conf}"
XDPH_TAG="${XDPH_TAG:?set XDPH_TAG in setup/versions.conf}"
LIBXKBCOMMON_TAG="${LIBXKBCOMMON_TAG:?set LIBXKBCOMMON_TAG in setup/versions.conf}"
WAYLAND_PROTOCOLS_TAG="${WAYLAND_PROTOCOLS_TAG:?set WAYLAND_PROTOCOLS_TAG in setup/versions.conf}"
LIBINPUT_TAG="${LIBINPUT_TAG:?set LIBINPUT_TAG in setup/versions.conf}"
RE2_TAG="${RE2_TAG:?set RE2_TAG in setup/versions.conf}"

stamp_payload() {
    cat <<EOF
hyprland=${HYPRLAND_TAG}
aquamarine=${AQUAMARINE_TAG}
hyprcursor=${HYPRCURSOR_TAG}
hyprgraphics=${HYPRGRAPHICS_TAG}
hypridle=${HYPRIDLE_TAG}
hyprland-guiutils=${HYPRLAND_GUIUTILS_TAG}
hyprland-protocols=${HYPRLAND_PROTOCOLS_TAG}
hyprland-qt-support=${HYPRLAND_QT_SUPPORT_TAG}
hyprlang=${HYPRLANG_TAG}
hyprlauncher=${HYPRLAUNCHER_TAG}
hyprlock=${HYPRLOCK_TAG}
hyprpaper=${HYPRPAPER_TAG}
hyprpicker=${HYPRPICKER_TAG}
hyprpolkitagent=${HYPRPOLKITAGENT_TAG}
hyprpwcenter=${HYPRPWCENTER_TAG}
hyprqt6engine=${HYPRQT6ENGINE_TAG}
hyprshutdown=${HYPRSHUTDOWN_TAG}
hyprsunset=${HYPRSUNSET_TAG}
hyprsysteminfo=${HYPRSYSTEMINFO_TAG}
hyprtoolkit=${HYPRTOOLKIT_TAG}
hyprutils=${HYPRUTILS_TAG}
hyprwayland-scanner=${HYPRWAYLAND_SCANNER_TAG}
hyprwire=${HYPRWIRE_TAG}
xdg-desktop-portal-hyprland=${XDPH_TAG}
libxkbcommon=${LIBXKBCOMMON_TAG}
wayland-protocols=${WAYLAND_PROTOCOLS_TAG}
libinput=${LIBINPUT_TAG}
re2=${RE2_TAG}
prefix=${PREFIX}
stdlib=libc++
EOF
}

install_build_deps() {
    local pkgs=() picked group
    local groups=(
        "clang" "llvm" "lld" "gcc-c++ gcc-c++-14 gcc" "cmake" "meson" "ninja ninja-build" "git"
        "pkgconf pkgconfig pkgconf-pkg-config" "jq" "cpio" "hwdata"
        "wayland-devel lib64wayland-devel" "wayland-protocols-devel wayland-protocols"
        "libdrm-devel lib64drm-devel lib64drm2-devel" "libxkbcommon-devel lib64xkbcommon-devel"
        "libinput-devel lib64input-devel" "libudev-devel systemd-devel lib64udev-devel"
        "libseat-devel seatd-devel lib64seat-devel seatd"
        "libglvnd-devel lib64glvnd-devel mesa-libEGL-devel lib64mesaegl-devel lib64EGL-devel"
        "libgbm-devel mesa-libgbm-devel lib64mesagbm-devel"
        "lib64mesaglesv2-devel lib64GLES-devel mesa-libGLES-devel libGLES-devel"
        "lib64mesagl-devel mesa-libGL-devel lib64GL-devel"
        "lib64cairo-devel cairo-devel" "lib64pango-devel lib64pango1.0-devel pango-devel"
        "lib64pixman-devel pixman-devel lib64pixman1-devel" "lib64xcb-devel libxcb-devel"
        "xcb-proto xcb-proto-devel lib64xcb-proto-devel" "lib64xcb-util-devel xcb-util-devel"
        "lib64xcb-util-wm-devel xcb-util-wm-devel" "lib64xcb-util-image-devel xcb-util-image-devel"
        "lib64xcb-util-keysyms-devel xcb-util-keysyms-devel"
        "lib64xcb-util-renderutil-devel xcb-util-renderutil-devel"
        "lib64xcb-util-errors-devel xcb-util-errors-devel libxcb-errors-devel"
        "lib64x11-devel libx11-devel libX11-devel" "lib64xcursor-devel libxcursor-devel libXcursor-devel"
        "lib64xcomposite-devel libxcomposite-devel libXcomposite-devel"
        "lib64xrender-devel libxrender-devel libXrender-devel"
        "lib64xfixes-devel libxfixes-devel libXfixes-devel"
        "xorg-x11-server-Xwayland-devel xwayland-devel Xwayland"
        "libdisplay-info-devel lib64display-info-devel" "libliftoff-devel lib64liftoff-devel"
        "tomlplusplus-devel lib64tomlplusplus-devel tomlplusplus" "re2-devel lib64re2-devel"
        "muparser-devel lib64muparser-devel" "glaze-devel lib64glaze-devel glaze"
        "glslang-devel glslang lib64glslang-devel" "lcms2-devel lib64lcms2-devel"
        "libjpeg-turbo-devel lib64jpeg-devel libjpeg-devel" "libwebp-devel lib64webp-devel"
        "libjxl-devel lib64jxl-devel" "libspng-devel lib64spng-devel" "libpng-devel lib64png-devel"
        "lib64magic-devel libmagic-devel file-devel magic-devel"
        "lib64rsvg2-devel librsvg2-devel lib64rsvg-devel librsvg-devel"
        "lib64heif-devel libheif-devel" "lib64zip-devel libzip-devel" "libuuid-devel lib64uuid-devel"
        "pugixml-devel lib64pugixml-devel" "lib64sdbus-cpp-devel sdbus-c++-devel sdbus-cpp-devel libsdbus-c++-devel"
        "lib64polkit-devel polkit-devel polkit" "lib64pipewire-devel pipewire-devel"
        "lib64ei-devel libei-devel libei" "lib64eis-devel libeis-devel"
        "lib64evdev-devel libevdev-devel" "lib64mtdev-devel mtdev-devel" "lib64xml2-devel libxml2-devel"
        "bison" "flex" "lib64canberra-devel libcanberra-devel"
        "lib64readline-devel readline-devel libreadline-devel"
        "lib64absl-devel abseil-cpp-devel libabsl-devel absl-devel"
        "lib64lua-devel lua-devel lua5.5-devel lua"
        "lib64Qt6Core-devel lib64qt6core-devel qt6-qtbase-devel qt6-base-devel"
        "lib64Qt6Gui-devel lib64Qt6Widgets-devel"
        "lib64Qt6Qml-devel qt6-qtdeclarative-devel qt6-qtqml-devel lib64qt6qml-devel"
        "lib64Qt6WaylandClient-devel lib64Qt6Wayland-devel qt6-qtwayland-devel lib64qt6wayland-devel"
        "qt6-qttools-devel lib64Qt6Tools-devel"
        "automake autoconf libtool xorg-x11-util-macros util-macros"
        "lib64c++-devel libc++-devel" "lib64c++abi-devel libc++abi-devel" "lib64unwind-devel libunwind-devel"
        "lib64iniparser-devel iniparser-devel"
    )
    for group in "${groups[@]}"; do
        # shellcheck disable=SC2086
        if picked="$(pick_pkg $group)"; then pkgs+=("$picked"); else warn "no package matched: $group"; fi
    done
    [[ "${#pkgs[@]}" -gt 0 ]] && ensure_packages "${pkgs[@]}"
}

use_libcxx() {
    case " ${CXXFLAGS:-} " in *" -stdlib=libc++ "*) ;; *) CXXFLAGS="${CXXFLAGS:+${CXXFLAGS} }-stdlib=libc++" ;; esac
    case " ${LDFLAGS:-} " in *" -stdlib=libc++ "*) ;; *) LDFLAGS="${LDFLAGS:+${LDFLAGS} }-stdlib=libc++" ;; esac
    export CXXFLAGS LDFLAGS
}

export_prefix_env() {
    use_libcxx
    export PATH="${PREFIX}/bin:${PATH:-/usr/bin}"
    export PKG_CONFIG_PATH="${PREFIX}/lib64/pkgconfig:${PREFIX}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
    export CMAKE_PREFIX_PATH="${PREFIX}${CMAKE_PREFIX_PATH:+:${CMAKE_PREFIX_PATH}}"
    export LD_LIBRARY_PATH="${PREFIX}/lib64:${PREFIX}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
}

ensure_tagged_repo() {
    local url="$1" dir="$2" ref="$3"
    if [[ -d "${dir}/.git" ]]; then
        log "fetch ${dir} (${ref})"
        [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && return 0
        git -C "$dir" fetch --tags --force --prune origin
    else
        [[ -e "$dir" ]] && die "${dir} exists but is not a git repository"
        log "clone ${url} -> ${dir}"
        [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && return 0
        git clone --recurse-submodules "$url" "$dir"
    fi
    [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && return 0
    git -C "$dir" checkout --detach "$ref" || git -C "$dir" checkout --detach "origin/${ref}"
    git -C "$dir" submodule update --init --recursive
}

patch_hyprland_python() {
    local f="${SRC_ROOT}/Hyprland/meta/generateLuaStubs.py"
    [[ -f "$f" ]] || return 0
    log "patch ${f} for pre-3.12 python"
    sed -i -E 's/^([ \t]*)type ([A-Za-z_][A-Za-z0-9_]*) = /\1\2 = /' "$f"
}

ensure_hyprland_tarball() {
    local dest="${SRC_ROOT}/Hyprland"
    local tarball="${SRC_ROOT}/source-${HYPRLAND_TAG}.tar.gz"
    local url="https://github.com/hyprwm/Hyprland/releases/download/${HYPRLAND_TAG}/source-${HYPRLAND_TAG}.tar.gz"
    if [[ -d "$dest" && -f "${dest}/CMakeLists.txt" ]]; then
        log "Hyprland sources already unpacked at ${dest}"
        patch_hyprland_python
        return 0
    fi
    log "fetch Hyprland ${HYPRLAND_TAG} release tarball"
    [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && return 0
    ensure_dir "$SRC_ROOT"
    if command -v curl >/dev/null 2>&1; then curl -fsSL -o "$tarball" "$url"; else wget -q -O "$tarball" "$url"; fi
    rm -rf "$dest"
    mkdir -p "$dest"
    tar -xzf "$tarball" -C "$dest" --strip-components=1
    patch_hyprland_python
}

cmake_config_flags=()
fill_cmake_config_flags() {
    use_libcxx
    CMAKE_EXE_LINKER_FLAGS="${LDFLAGS:-}"
    case " ${CMAKE_EXE_LINKER_FLAGS} " in *" --allow-shlib-undefined "*) ;; *) CMAKE_EXE_LINKER_FLAGS="${CMAKE_EXE_LINKER_FLAGS:+${CMAKE_EXE_LINKER_FLAGS} }-Wl,--allow-shlib-undefined" ;; esac
    cmake_config_flags=(
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_PREFIX_PATH="$PREFIX"
        -DCMAKE_INSTALL_LIBDIR=lib64 -DCMAKE_INSTALL_RPATH="${PREFIX}/lib64;${PREFIX}/lib"
        -DCMAKE_BUILD_RPATH="${PREFIX}/lib64;${PREFIX}/lib" -DBUILD_TESTING=OFF
        -DCMAKE_C_COMPILER="${CMAKE_C_COMPILER:-${CC:-clang}}"
        -DCMAKE_CXX_COMPILER="${CMAKE_CXX_COMPILER:-${CXX:-clang++}}"
        "-DCMAKE_C_FLAGS=${CFLAGS:-}" "-DCMAKE_CXX_FLAGS=${CXXFLAGS:-}"
        "-DCMAKE_EXE_LINKER_FLAGS=${CMAKE_EXE_LINKER_FLAGS}"
        "-DCMAKE_SHARED_LINKER_FLAGS=${LDFLAGS:-}" "-DCMAKE_MODULE_LINKER_FLAGS=${LDFLAGS:-}"
    )
    [[ -n "${AR:-}" ]] && cmake_config_flags+=("-DCMAKE_AR=${AR}")
    [[ -n "${RANLIB:-}" ]] && cmake_config_flags+=("-DCMAKE_RANLIB=${RANLIB}")
}

cmake_skip_target() {
    case "$1" in
        *test*|*Test*|*tests*|hyprgraphics_image|hyprgraphics_arg|simpleWindow|commitThread|attachments|output) return 0 ;;
        check-*|generate-lua-stubs|*lua-stub*) return 0 ;;
    esac
    return 1
}

cmake_installable_targets() {
    local build="$1" dir base
    shopt -s nullglob
    for dir in "${build}/CMakeFiles"/*.dir "${build}"/*/CMakeFiles/*.dir; do
        [[ -d "$dir" ]] || continue
        base="$(basename "$dir" .dir)"
        cmake_skip_target "$base" && continue
        printf '%s\n' "$base"
    done
}

build_cmake_src() {
    local src="$1"; shift || true
    local extra=("$@") jobs targets=() t build_args=()
    [[ -f "${src}/CMakeLists.txt" ]] || die "no CMakeLists.txt in ${src}"
    [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && { log "would cmake-build ${src} -> ${PREFIX}"; return 0; }
    rm -rf "${src}/build"
    fill_cmake_config_flags
    cmake -S "$src" -B "${src}/build" "${cmake_config_flags[@]}" "${extra[@]}"
    jobs="$(nproc)"
    while IFS= read -r t; do [[ -n "$t" ]] && targets+=("$t"); done < <(cmake_installable_targets "${src}/build" | sort -u)
    if [[ "${#targets[@]}" -gt 0 ]]; then
        for t in "${targets[@]}"; do build_args+=(--target "$t"); done
        log "cmake targets: ${targets[*]}"
        cmake --build "${src}/build" --config Release -j"$jobs" "${build_args[@]}"
    else
        cmake --build "${src}/build" --config Release -j"$jobs"
    fi
    sudo cmake --install "${src}/build"
}

build_meson_src() {
    local src="$1"; shift || true
    local extra=("$@")
    [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && { log "would meson-build ${src} -> ${PREFIX}"; return 0; }
    rm -rf "${src}/build"
    meson setup "${src}/build" "$src" --prefix="$PREFIX" --libdir=lib64 --buildtype=release \
        --pkg-config-path="${PREFIX}/lib64/pkgconfig:${PREFIX}/lib/pkgconfig" "${extra[@]}"
    meson compile -C "${src}/build"
    sudo meson install -C "${src}/build"
}

pkg_ver_ge() {
    local have="$1" need="$2"
    [[ "$(printf '%s\n' "$need" "$have" | sort -V | tail -1)" == "$have" ]]
}

ensure_pkg_or_build() {
    local mod="$1" min="$2" have
    if pkg-config --exists "$mod" 2>/dev/null; then
        have="$(pkg-config --modversion "$mod")"
        if pkg_ver_ge "$have" "$min"; then log "${mod} ${have} satisfies >= ${min}"; return 1; fi
        log "${mod} ${have} is older than ${min}; building into prefix"
    else
        log "${mod} missing; building into prefix"
    fi
    return 0
}

ensure_wayland_protocols() {
    if ! ensure_pkg_or_build wayland-protocols 1.49; then return 0; fi
    ensure_tagged_repo https://gitlab.freedesktop.org/wayland/wayland-protocols.git \
        "${SRC_ROOT}/wayland-protocols" "$WAYLAND_PROTOCOLS_TAG"
    local src="${SRC_ROOT}/wayland-protocols" dest="${PREFIX}/share/wayland-protocols"
    local pc="${PREFIX}/lib64/pkgconfig/wayland-protocols.pc" d
    [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && return 0
    sudo rm -rf "$dest"
    sudo mkdir -p "$dest" "$(dirname "$pc")"
    for d in stable staging unstable experimental; do
        [[ -d "${src}/${d}" ]] && sudo cp -a "${src}/${d}" "${dest}/"
    done
    sudo tee "$pc" >/dev/null <<EOF
prefix=${PREFIX}
datarootdir=\${prefix}/share
pkgdatadir=\${datarootdir}/wayland-protocols

Name: Wayland Protocols
Description: Wayland protocol files
Version: ${WAYLAND_PROTOCOLS_TAG}
EOF
}

ensure_libxkbcommon() {
    if ! ensure_pkg_or_build xkbcommon 1.11.0; then return 0; fi
    ensure_tagged_repo https://github.com/xkbcommon/libxkbcommon.git "${SRC_ROOT}/libxkbcommon" "$LIBXKBCOMMON_TAG"
    build_meson_src "${SRC_ROOT}/libxkbcommon" -Denable-docs=false -Denable-wayland=false -Denable-x11=true -Denable-xkbregistry=true
}

ensure_libinput() {
    if ! ensure_pkg_or_build libinput 1.29; then return 0; fi
    ensure_tagged_repo https://gitlab.freedesktop.org/libinput/libinput.git "${SRC_ROOT}/libinput" "$LIBINPUT_TAG"
    build_meson_src "${SRC_ROOT}/libinput" -Dtests=false -Ddocumentation=false -Ddebug-gui=false -Dlibwacom=false
}

ensure_re2() {
    ensure_tagged_repo https://github.com/google/re2.git "${SRC_ROOT}/re2" "$RE2_TAG"
    build_cmake_src "${SRC_ROOT}/re2" -DRE2_TEST=OFF -DRE2_BENCHMARK=OFF -DBUILD_SHARED_LIBS=ON
}

ensure_iniparser_pc() {
    local so="" inc="/usr/include"
    for cand in /usr/lib64/libiniparser.so /usr/lib/libiniparser.so; do [[ -e "$cand" ]] && { so="$cand"; break; }; done
    [[ -n "$so" ]] || die "libiniparser.so missing; install lib64iniparser-devel"
    if [[ -f /usr/include/iniparser/iniparser.h ]]; then inc=/usr/include/iniparser
    elif [[ -f /usr/include/iniparser.h ]]; then inc=/usr/include
    else die "iniparser.h missing; install lib64iniparser-devel"; fi
    local pc="${PREFIX}/lib64/pkgconfig/iniparser.pc"
    log "write ${pc} (includedir=${inc})"
    [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && return 0
    sudo mkdir -p "$(dirname "$pc")"
    sudo tee "$pc" >/dev/null <<EOF
prefix=/usr
exec_prefix=\${prefix}
libdir=$(dirname "$so")
includedir=${inc}
Name: iniparser
Description: INI file parser
Version: 4.2.1
Libs: -L\${libdir} -liniparser
Cflags: -I\${includedir} -I/usr/include
EOF
}

maybe_build_xcb_errors() {
    if pkg-config --exists xcb-errors 2>/dev/null; then log "xcb-errors already present"; return 0; fi
    warn "xcb-errors missing; building into ${PREFIX}"
    ensure_tagged_repo "https://gitlab.freedesktop.org/xorg/lib/libxcb-errors.git" "${SRC_ROOT}/libxcb-errors" "master"
    [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && return 0
    ( cd "${SRC_ROOT}/libxcb-errors" && ./autogen.sh --prefix="$PREFIX" && make -j"$(nproc)" && sudo make install )
}

install_session_files() {
    local wrapper_dest="${PREFIX}/bin/start-hyprland-source" desktop_name="hyprland-source.desktop"
    [[ -f "$SESSION_WRAPPER_SRC" ]] || die "missing ${SESSION_WRAPPER_SRC}"
    [[ -f "$SESSION_DESKTOP_SRC" ]] || die "missing ${SESSION_DESKTOP_SRC}"
    [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && { log "would install Ly session ${desktop_name}"; return 0; }
    sudo install -d "${PREFIX}/bin" "${PREFIX}/share/wayland-sessions" "$LY_CUSTOM_DIR" "$WAYLAND_SESSION_DIR"
    sudo install -m 0755 "$SESSION_WRAPPER_SRC" "$wrapper_dest"
    sudo install -m 0644 "$SESSION_DESKTOP_SRC" "${PREFIX}/share/wayland-sessions/${desktop_name}"
    sudo install -m 0644 "$SESSION_DESKTOP_SRC" "${WAYLAND_SESSION_DIR}/${desktop_name}"
    sudo install -m 0644 "$SESSION_DESKTOP_SRC" "${LY_CUSTOM_DIR}/${desktop_name}"
    if [[ "$PREFIX" != "$TEMPLATE_PREFIX" ]]; then
        sudo sed -i -E "s|${TEMPLATE_PREFIX}|${PREFIX}|g" "$wrapper_dest" \
            "${PREFIX}/share/wayland-sessions/${desktop_name}" "${WAYLAND_SESSION_DIR}/${desktop_name}" "${LY_CUSTOM_DIR}/${desktop_name}"
    fi
    sudo sed -i -E "s|source 0\\.56\\.2|source ${HYPRLAND_SOURCE_VERSION}|g; s|v0\\.56\\.2|${HYPRLAND_TAG}|g" \
        "${PREFIX}/share/wayland-sessions/${desktop_name}" "${WAYLAND_SESSION_DIR}/${desktop_name}" "${LY_CUSTOM_DIR}/${desktop_name}"
}

set_ly_key() {
    local file="$1" key="$2" value="$3"
    [[ -f "$file" ]] || return 1
    if grep -qE "^${key}[[:space:]]*=" "$file"; then
        grep -qE "^${key}[[:space:]]*=[[:space:]]*${value}$" "$file" && return 0
        log "set ${key} in ${file}"
        [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]] && sudo sed -i -E "s|^${key}[[:space:]]*=.*|${key} = ${value}|" "$file"
        return 0
    fi
    log "add ${key} to ${file}"
    [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]] && printf '%s = %s\n' "$key" "$value" | sudo tee -a "$file" >/dev/null
}

configure_ly_source_session() {
    if [[ -f /etc/ly/config.ini ]]; then set_ly_key /etc/ly/config.ini custom_sessions "$LY_CUSTOM_DIR"
    elif [[ -f /etc/ly/config.lua ]]; then
        if grep -qE "^[[:space:]]*custom_sessions[[:space:]]*=" /etc/ly/config.lua; then log "leave custom_sessions in /etc/ly/config.lua"
        else warn "/etc/ly/config.lua has no custom_sessions"; fi
    else warn "Ly config not present yet"; fi
}

build_stack() {
    export_prefix_env
    log "compiler ${CC:-unset} / ${CXX:-unset} CFLAGS=${CFLAGS:-} CXXFLAGS=${CXXFLAGS:-} LDFLAGS=${LDFLAGS:-}"
    ensure_dir "$SRC_ROOT"
    [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]] && sudo mkdir -p "$PREFIX"
    maybe_build_xcb_errors
    ensure_iniparser_pc
    ensure_tagged_repo https://github.com/hyprwm/hyprwayland-scanner.git "${SRC_ROOT}/hyprwayland-scanner" "$HYPRWAYLAND_SCANNER_TAG"
    build_cmake_src "${SRC_ROOT}/hyprwayland-scanner"
    ensure_tagged_repo https://github.com/hyprwm/hyprutils.git "${SRC_ROOT}/hyprutils" "$HYPRUTILS_TAG"
    build_cmake_src "${SRC_ROOT}/hyprutils"
    ensure_tagged_repo https://github.com/hyprwm/hyprlang.git "${SRC_ROOT}/hyprlang" "$HYPRLANG_TAG"
    build_cmake_src "${SRC_ROOT}/hyprlang"
    ensure_tagged_repo https://github.com/hyprwm/hyprgraphics.git "${SRC_ROOT}/hyprgraphics" "$HYPRGRAPHICS_TAG"
    build_cmake_src "${SRC_ROOT}/hyprgraphics"
    ensure_tagged_repo https://github.com/hyprwm/hyprcursor.git "${SRC_ROOT}/hyprcursor" "$HYPRCURSOR_TAG"
    build_cmake_src "${SRC_ROOT}/hyprcursor"
    ensure_tagged_repo https://github.com/hyprwm/hyprland-protocols.git "${SRC_ROOT}/hyprland-protocols" "$HYPRLAND_PROTOCOLS_TAG"
    build_meson_src "${SRC_ROOT}/hyprland-protocols"
    ensure_tagged_repo https://github.com/hyprwm/aquamarine.git "${SRC_ROOT}/aquamarine" "$AQUAMARINE_TAG"
    build_cmake_src "${SRC_ROOT}/aquamarine"
    ensure_tagged_repo https://github.com/hyprwm/hyprwire.git "${SRC_ROOT}/hyprwire" "$HYPRWIRE_TAG"
    build_cmake_src "${SRC_ROOT}/hyprwire"
    ensure_tagged_repo https://github.com/hyprwm/hyprtoolkit.git "${SRC_ROOT}/hyprtoolkit" "$HYPRTOOLKIT_TAG"
    build_cmake_src "${SRC_ROOT}/hyprtoolkit"
    ensure_wayland_protocols
    ensure_libxkbcommon
    ensure_libinput
    ensure_re2
    ensure_hyprland_tarball
    build_cmake_src "${SRC_ROOT}/Hyprland" -DNO_UWSM:STRING=true -DCMAKE_DISABLE_PRECOMPILE_HEADERS=ON
    ensure_tagged_repo https://github.com/hyprwm/hyprland-qt-support.git "${SRC_ROOT}/hyprland-qt-support" "$HYPRLAND_QT_SUPPORT_TAG"
    build_cmake_src "${SRC_ROOT}/hyprland-qt-support"
    ensure_tagged_repo https://github.com/hyprwm/hyprqt6engine.git "${SRC_ROOT}/hyprqt6engine" "$HYPRQT6ENGINE_TAG"
    build_cmake_src "${SRC_ROOT}/hyprqt6engine"
    ensure_tagged_repo https://github.com/hyprwm/hyprland-guiutils.git "${SRC_ROOT}/hyprland-guiutils" "$HYPRLAND_GUIUTILS_TAG"
    build_cmake_src "${SRC_ROOT}/hyprland-guiutils"
    ensure_tagged_repo https://github.com/hyprwm/hypridle.git "${SRC_ROOT}/hypridle" "$HYPRIDLE_TAG"
    build_cmake_src "${SRC_ROOT}/hypridle"
    ensure_tagged_repo https://github.com/hyprwm/hyprlock.git "${SRC_ROOT}/hyprlock" "$HYPRLOCK_TAG"
    build_cmake_src "${SRC_ROOT}/hyprlock"
    ensure_tagged_repo https://github.com/hyprwm/hyprpaper.git "${SRC_ROOT}/hyprpaper" "$HYPRPAPER_TAG"
    build_cmake_src "${SRC_ROOT}/hyprpaper"
    ensure_tagged_repo https://github.com/hyprwm/hyprpicker.git "${SRC_ROOT}/hyprpicker" "$HYPRPICKER_TAG"
    build_cmake_src "${SRC_ROOT}/hyprpicker"
    ensure_tagged_repo https://github.com/hyprwm/hyprpolkitagent.git "${SRC_ROOT}/hyprpolkitagent" "$HYPRPOLKITAGENT_TAG"
    build_cmake_src "${SRC_ROOT}/hyprpolkitagent"
    ensure_tagged_repo https://github.com/hyprwm/hyprlauncher.git "${SRC_ROOT}/hyprlauncher" "$HYPRLAUNCHER_TAG"
    build_cmake_src "${SRC_ROOT}/hyprlauncher"
    ensure_tagged_repo https://github.com/hyprwm/hyprpwcenter.git "${SRC_ROOT}/hyprpwcenter" "$HYPRPWCENTER_TAG"
    build_cmake_src "${SRC_ROOT}/hyprpwcenter"
    ensure_tagged_repo https://github.com/hyprwm/hyprsunset.git "${SRC_ROOT}/hyprsunset" "$HYPRSUNSET_TAG"
    build_cmake_src "${SRC_ROOT}/hyprsunset"
    ensure_tagged_repo https://github.com/hyprwm/hyprsysteminfo.git "${SRC_ROOT}/hyprsysteminfo" "$HYPRSYSTEMINFO_TAG"
    build_cmake_src "${SRC_ROOT}/hyprsysteminfo"
    ensure_tagged_repo https://github.com/hyprwm/hyprshutdown.git "${SRC_ROOT}/hyprshutdown" "$HYPRSHUTDOWN_TAG"
    build_cmake_src "${SRC_ROOT}/hyprshutdown"
    ensure_tagged_repo https://github.com/hyprwm/xdg-desktop-portal-hyprland.git "${SRC_ROOT}/xdg-desktop-portal-hyprland" "$XDPH_TAG"
    build_cmake_src "${SRC_ROOT}/xdg-desktop-portal-hyprland"
}

write_stamp() {
    [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && return 0
    sudo mkdir -p "$(dirname "$STAMP")"
    stamp_payload | sudo tee "$STAMP" >/dev/null
}

if [[ -x "${PREFIX}/bin/Hyprland" && -f "$STAMP" ]] && [[ "$(cat "$STAMP")" == "$(stamp_payload)" ]] && [[ "${HYPRLAND_SOURCE_FORCE:-0}" != "1" ]]; then
    log "Hyprland ${HYPRLAND_SOURCE_VERSION} prefix already current at ${PREFIX}"
    install_session_files
    configure_ly_source_session
    exit 0
fi

install_build_deps
command -v clang >/dev/null 2>&1 || die "clang is not on PATH after package install"
command -v clang++ >/dev/null 2>&1 || die "clang++ is not on PATH after package install"
command -v cmake >/dev/null 2>&1 || die "cmake is not on PATH after package install"
command -v meson >/dev/null 2>&1 || die "meson is not on PATH after package install"

if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
    log "would build Hyprland ${HYPRLAND_TAG} and ecosystem into ${PREFIX}"
    install_session_files
    configure_ly_source_session
    exit 0
fi

build_stack
install_session_files
configure_ly_source_session
write_stamp

if [[ -x "${PREFIX}/bin/Hyprland" ]]; then
    log "installed ${HYPRLAND_TAG} to ${PREFIX} (Ly session: Hyprland (source ${HYPRLAND_SOURCE_VERSION}))"
else
    die "build finished but ${PREFIX}/bin/Hyprland is missing"
fi
