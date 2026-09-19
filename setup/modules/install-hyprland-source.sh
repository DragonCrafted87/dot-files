#!/usr/bin/env bash
# Build Hyprland v0.56.2 plus the hypr* ecosystem into an isolated prefix.
# Distro packages from install-hyprland-session stay in /usr. Ly gets a
# second session so the two stacks can be chosen independently.
#
# Fedora discussion #284 is the closest published dep list; package names
# below are the OpenMandriva translations of that set plus current hypr*
# build requirements (C++26, cmake, Qt6 for a few utilities).

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

HYPRLAND_SOURCE_VERSION="${HYPRLAND_SOURCE_VERSION:-v0.56.2}"
PREFIX="${HYPRLAND_SOURCE_PREFIX:-/opt/hyprland-0.56.2}"
SRC_ROOT="${HYPRLAND_SOURCE_SRC:-${DOTFILES_HOME}/.cache/hyprland-source}"
STAMP="${PREFIX}/share/hyprland-source/.dotfiles-stamp"
SESSION_DESKTOP_SRC="${SETUP_FILES_DIR}/hyprland-source/hyprland-source.desktop"
SESSION_WRAPPER_SRC="${SETUP_FILES_DIR}/hyprland-source/start-hyprland-source.sh"
LY_CUSTOM_DIR="/etc/ly/custom-sessions"
WAYLAND_SESSION_DIR="/usr/share/wayland-sessions"

# Pinned to the Debian-Hyprland / Fedora COPR 0.56.2 set. Override a
# single tag without editing the module.
AQUAMARINE_TAG="${AQUAMARINE_TAG:-v0.15.1}"
HYPRCURSOR_TAG="${HYPRCURSOR_TAG:-v0.1.13}"
HYPRGRAPHICS_TAG="${HYPRGRAPHICS_TAG:-v0.5.1}"
HYPRIDLE_TAG="${HYPRIDLE_TAG:-v0.1.8}"
HYPRLAND_GUIUTILS_TAG="${HYPRLAND_GUIUTILS_TAG:-v0.2.2}"
HYPRLAND_PROTOCOLS_TAG="${HYPRLAND_PROTOCOLS_TAG:-v0.7.0}"
HYPRLAND_QT_SUPPORT_TAG="${HYPRLAND_QT_SUPPORT_TAG:-v0.1.0}"
HYPRLAND_TAG="${HYPRLAND_TAG:-v0.56.2}"
HYPRLANG_TAG="${HYPRLANG_TAG:-v0.6.8}"
HYPRLAUNCHER_TAG="${HYPRLAUNCHER_TAG:-v0.1.6}"
HYPRLOCK_TAG="${HYPRLOCK_TAG:-v0.9.6}"
HYPRPAPER_TAG="${HYPRPAPER_TAG:-v0.8.4}"
HYPRPICKER_TAG="${HYPRPICKER_TAG:-v0.4.7}"
HYPRPOLKITAGENT_TAG="${HYPRPOLKITAGENT_TAG:-v0.2.0}"
HYPRPWCENTER_TAG="${HYPRPWCENTER_TAG:-v0.1.2}"
HYPRQT6ENGINE_TAG="${HYPRQT6ENGINE_TAG:-v0.1.0}"
HYPRSHUTDOWN_TAG="${HYPRSHUTDOWN_TAG:-v0.1.1}"
HYPRSUNSET_TAG="${HYPRSUNSET_TAG:-v0.4.0}"
HYPRSYSTEMINFO_TAG="${HYPRSYSTEMINFO_TAG:-v0.2.0}"
HYPRTOOLKIT_TAG="${HYPRTOOLKIT_TAG:-v0.6.0}"
HYPRUTILS_TAG="${HYPRUTILS_TAG:-v0.14.2}"
HYPRWAYLAND_SCANNER_TAG="${HYPRWAYLAND_SCANNER_TAG:-v0.4.6}"
HYPRWIRE_TAG="${HYPRWIRE_TAG:-v0.3.1}"
XDPH_TAG="${XDPH_TAG:-v1.4.1}"

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
prefix=${PREFIX}
EOF
}

# dnf list is case-insensitive and will find libX11-devel when the
# rpm is libx11-devel. Require an exact name before we hand it to install.
pkg_name_exists() {
    local name="$1" resolved
    if rpm -q "$name" >/dev/null 2>&1; then
        return 0
    fi
    resolved="$(dnf repoquery -q --qf '%{name}' "$name" 2>/dev/null | head -n1 || true)"
    [[ "$resolved" == "$name" ]]
}

pick_pkg() {
    local p
    for p in "$@"; do
        if pkg_name_exists "$p"; then
            printf '%s\n' "$p"
            return 0
        fi
    done
    return 1
}

install_build_deps() {
    local pkgs=() picked group
    local groups=(
        "clang"
        "llvm"
        "lld"
        "gcc-c++ gcc-c++-14 gcc"
        "cmake"
        "meson"
        "ninja ninja-build"
        "git"
        "pkgconf pkgconfig pkgconf-pkg-config"
        "jq"
        "cpio"
        "hwdata"
        "wayland-devel lib64wayland-devel"
        "wayland-protocols-devel wayland-protocols"
        "libdrm-devel lib64drm-devel lib64drm2-devel"
        "libxkbcommon-devel lib64xkbcommon-devel"
        "libinput-devel lib64input-devel"
        "libudev-devel systemd-devel lib64udev-devel"
        "libseat-devel seatd-devel lib64seat-devel seatd"
        "libglvnd-devel lib64glvnd-devel mesa-libEGL-devel lib64mesaegl-devel lib64EGL-devel"
        "libgbm-devel mesa-libgbm-devel lib64mesagbm-devel"
        "lib64mesaglesv2-devel lib64GLES-devel mesa-libGLES-devel libGLES-devel"
        "lib64mesagl-devel mesa-libGL-devel lib64GL-devel"
        "lib64cairo-devel cairo-devel"
        "lib64pango-devel lib64pango1.0-devel pango-devel"
        "lib64pixman-devel pixman-devel lib64pixman1-devel"
        "lib64xcb-devel libxcb-devel"
        "xcb-proto xcb-proto-devel lib64xcb-proto-devel"
        "lib64xcb-util-devel xcb-util-devel"
        "lib64xcb-util-wm-devel xcb-util-wm-devel"
        "lib64xcb-util-image-devel xcb-util-image-devel"
        "lib64xcb-util-keysyms-devel xcb-util-keysyms-devel"
        "lib64xcb-util-renderutil-devel xcb-util-renderutil-devel"
        "lib64xcb-util-errors-devel xcb-util-errors-devel libxcb-errors-devel"
        "lib64x11-devel libx11-devel libX11-devel"
        "lib64xcursor-devel libxcursor-devel libXcursor-devel"
        "lib64xcomposite-devel libxcomposite-devel libXcomposite-devel"
        "lib64xrender-devel libxrender-devel libXrender-devel"
        "lib64xfixes-devel libxfixes-devel libXfixes-devel"
        "xorg-x11-server-Xwayland-devel xwayland-devel Xwayland"
        "libdisplay-info-devel lib64display-info-devel"
        "libliftoff-devel lib64liftoff-devel"
        "tomlplusplus-devel lib64tomlplusplus-devel tomlplusplus"
        "re2-devel lib64re2-devel"
        "muparser-devel lib64muparser-devel"
        "glaze-devel lib64glaze-devel glaze"
        "glslang-devel glslang lib64glslang-devel"
        "lcms2-devel lib64lcms2-devel"
        "libjpeg-turbo-devel lib64jpeg-devel libjpeg-devel"
        "libwebp-devel lib64webp-devel"
        "libjxl-devel lib64jxl-devel"
        "libspng-devel lib64spng-devel"
        "libpng-devel lib64png-devel"
        "libuuid-devel lib64uuid-devel"
        "pugixml-devel lib64pugixml-devel"
        "lib64sdbus-cpp-devel sdbus-c++-devel sdbus-cpp-devel libsdbus-c++-devel"
        "lib64polkit-devel polkit-devel polkit"
        "lib64pipewire-devel pipewire-devel"
        "lib64ei-devel libei-devel libei"
        "lib64lua-devel lua-devel lua5.5-devel lua"
        "lib64Qt6Core-devel lib64qt6core-devel qt6-qtbase-devel qt6-base-devel"
        "lib64Qt6Gui-devel lib64Qt6Widgets-devel"
        "lib64Qt6Qml-devel qt6-qtdeclarative-devel qt6-qtqml-devel lib64qt6qml-devel"
        "lib64Qt6WaylandClient-devel lib64Qt6Wayland-devel qt6-qtwayland-devel lib64qt6wayland-devel"
        "qt6-qttools-devel lib64Qt6Tools-devel"
        "automake autoconf libtool xorg-x11-util-macros util-macros"
    )

    for group in "${groups[@]}"; do
        # shellcheck disable=SC2086
        if picked="$(pick_pkg $group)"; then
            pkgs+=("$picked")
        else
            warn "no package matched: $group"
        fi
    done
    [[ "${#pkgs[@]}" -gt 0 ]] && ensure_packages "${pkgs[@]}"
}

export_prefix_env() {
    export PATH="${PREFIX}/bin:${PATH:-/usr/bin}"
    export PKG_CONFIG_PATH="${PREFIX}/lib64/pkgconfig:${PREFIX}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
    export CMAKE_PREFIX_PATH="${PREFIX}${CMAKE_PREFIX_PATH:+:${CMAKE_PREFIX_PATH}}"
    export LD_LIBRARY_PATH="${PREFIX}/lib64:${PREFIX}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
    export CC="${CC:-clang}"
    export CXX="${CXX:-clang++}"
    if command -v ld.lld >/dev/null 2>&1; then
        export LDFLAGS="${LDFLAGS:-} -fuse-ld=lld"
    fi
}

ensure_tagged_repo() {
    local url="$1"
    local dir="$2"
    local ref="$3"

    if [[ -d "${dir}/.git" ]]; then
        log "fetch ${dir} (${ref})"
        if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
            return 0
        fi
        git -C "$dir" fetch --tags --force --prune origin
    else
        if [[ -e "$dir" ]]; then
            die "${dir} exists but is not a git repository"
        fi
        log "clone ${url} -> ${dir}"
        if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
            return 0
        fi
        git clone --recurse-submodules "$url" "$dir"
    fi

    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        return 0
    fi
    if ! git -C "$dir" checkout --detach "$ref"; then
        git -C "$dir" checkout --detach "origin/${ref}"
    fi
    git -C "$dir" submodule update --init --recursive
}

ensure_hyprland_tarball() {
    local dest="${SRC_ROOT}/Hyprland"
    local tarball="${SRC_ROOT}/source-${HYPRLAND_TAG}.tar.gz"
    local url="https://github.com/hyprwm/Hyprland/releases/download/${HYPRLAND_TAG}/source-${HYPRLAND_TAG}.tar.gz"

    if [[ -d "$dest" && -f "${dest}/CMakeLists.txt" ]]; then
        log "Hyprland sources already unpacked at ${dest}"
        return 0
    fi
    log "fetch Hyprland ${HYPRLAND_TAG} release tarball"
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        return 0
    fi
    ensure_dir "$SRC_ROOT"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tarball" "$url"
    else
        wget -q -O "$tarball" "$url"
    fi
    rm -rf "$dest"
    mkdir -p "$dest"
    tar -xzf "$tarball" -C "$dest" --strip-components=1
}

cmake_flags() {
    printf '%s\n' \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_PREFIX_PATH="$PREFIX" \
        -DCMAKE_INSTALL_LIBDIR=lib64 \
        -DCMAKE_INSTALL_RPATH="${PREFIX}/lib64;${PREFIX}/lib" \
        -DCMAKE_BUILD_RPATH="${PREFIX}/lib64;${PREFIX}/lib" \
        -DCMAKE_C_COMPILER="${CC:-clang}" \
        -DCMAKE_CXX_COMPILER="${CXX:-clang++}"
}

build_cmake_src() {
    local src="$1"
    shift || true
    local extra=("$@")

    [[ -f "${src}/CMakeLists.txt" ]] || die "no CMakeLists.txt in ${src}"
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        log "would cmake-build ${src} -> ${PREFIX}"
        return 0
    fi
    rm -rf "${src}/build"
    # shellcheck disable=SC2046
    cmake -S "$src" -B "${src}/build" $(cmake_flags) "${extra[@]}"
    cmake --build "${src}/build" --config Release -j"$(nproc)"
    sudo cmake --install "${src}/build"
}

build_meson_src() {
    local src="$1"
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        log "would meson-build ${src} -> ${PREFIX}"
        return 0
    fi
    rm -rf "${src}/build"
    meson setup "${src}/build" "$src" \
        --prefix="$PREFIX" \
        --libdir=lib64 \
        --buildtype=release \
        --pkg-config-path="${PREFIX}/lib64/pkgconfig:${PREFIX}/lib/pkgconfig"
    meson compile -C "${src}/build"
    sudo meson install -C "${src}/build"
}

maybe_build_xcb_errors() {
    if pkg-config --exists xcb-errors 2>/dev/null; then
        log "xcb-errors already present"
        return 0
    fi
    warn "xcb-errors missing; building into ${PREFIX}"
    ensure_tagged_repo \
        "https://gitlab.freedesktop.org/xorg/lib/libxcb-errors.git" \
        "${SRC_ROOT}/libxcb-errors" \
        "master"
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        return 0
    fi
    (
        cd "${SRC_ROOT}/libxcb-errors"
        ./autogen.sh --prefix="$PREFIX"
        make -j"$(nproc)"
        sudo make install
    )
}

install_session_files() {
    local wrapper_dest="${PREFIX}/bin/start-hyprland-source"
    local desktop_name="hyprland-source.desktop"

    [[ -f "$SESSION_WRAPPER_SRC" ]] || die "missing ${SESSION_WRAPPER_SRC}"
    [[ -f "$SESSION_DESKTOP_SRC" ]] || die "missing ${SESSION_DESKTOP_SRC}"

    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        log "would install Ly session ${desktop_name} and ${wrapper_dest}"
        return 0
    fi

    sudo install -d "${PREFIX}/bin" "${PREFIX}/share/wayland-sessions" \
        "$LY_CUSTOM_DIR" "$WAYLAND_SESSION_DIR"
    sudo install -m 0755 "$SESSION_WRAPPER_SRC" "$wrapper_dest"
    if [[ "$PREFIX" != "/opt/hyprland-0.56.2" ]]; then
        sudo sed -i -E \
            "s|/opt/hyprland-0.56.2|${PREFIX}|g" \
            "$wrapper_dest"
    fi
    sudo install -m 0644 "$SESSION_DESKTOP_SRC" \
        "${PREFIX}/share/wayland-sessions/${desktop_name}"
    sudo install -m 0644 "$SESSION_DESKTOP_SRC" \
        "${WAYLAND_SESSION_DIR}/${desktop_name}"
    sudo install -m 0644 "$SESSION_DESKTOP_SRC" \
        "${LY_CUSTOM_DIR}/${desktop_name}"
    if [[ "$PREFIX" != "/opt/hyprland-0.56.2" ]]; then
        sudo sed -i -E \
            "s|/opt/hyprland-0.56.2|${PREFIX}|g" \
            "${PREFIX}/share/wayland-sessions/${desktop_name}" \
            "${WAYLAND_SESSION_DIR}/${desktop_name}" \
            "${LY_CUSTOM_DIR}/${desktop_name}"
    fi
}

set_ly_key() {
    local file="$1"
    local key="$2"
    local value="$3"

    if [[ ! -f "$file" ]]; then
        return 1
    fi
    if grep -qE "^${key}[[:space:]]*=" "$file"; then
        if grep -qE "^${key}[[:space:]]*=[[:space:]]*${value}$" "$file"; then
            return 0
        fi
        log "set ${key} in ${file}"
        if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
            sudo sed -i -E "s|^${key}[[:space:]]*=.*|${key} = ${value}|" "$file"
        fi
        return 0
    fi
    log "add ${key} to ${file}"
    if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
        printf '%s = %s\n' "$key" "$value" | sudo tee -a "$file" >/dev/null
    fi
}

configure_ly_source_session() {
    if [[ -f /etc/ly/config.ini ]]; then
        set_ly_key /etc/ly/config.ini custom_sessions "$LY_CUSTOM_DIR"
    elif [[ -f /etc/ly/config.lua ]]; then
        if grep -qE "^[[:space:]]*custom_sessions[[:space:]]*=" /etc/ly/config.lua; then
            log "leave custom_sessions in /etc/ly/config.lua (already set)"
        else
            warn "/etc/ly/config.lua has no custom_sessions; session file also installed under ${WAYLAND_SESSION_DIR}"
        fi
    else
        warn "Ly config not present yet; session desktop is in ${LY_CUSTOM_DIR} and ${WAYLAND_SESSION_DIR}"
    fi
}

build_stack() {
    export_prefix_env
    ensure_dir "$SRC_ROOT"
    if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
        sudo mkdir -p "$PREFIX"
    fi

    maybe_build_xcb_errors

    ensure_tagged_repo https://github.com/hyprwm/hyprwayland-scanner.git \
        "${SRC_ROOT}/hyprwayland-scanner" "$HYPRWAYLAND_SCANNER_TAG"
    build_cmake_src "${SRC_ROOT}/hyprwayland-scanner"

    ensure_tagged_repo https://github.com/hyprwm/hyprutils.git \
        "${SRC_ROOT}/hyprutils" "$HYPRUTILS_TAG"
    build_cmake_src "${SRC_ROOT}/hyprutils"

    ensure_tagged_repo https://github.com/hyprwm/hyprlang.git \
        "${SRC_ROOT}/hyprlang" "$HYPRLANG_TAG"
    build_cmake_src "${SRC_ROOT}/hyprlang"

    ensure_tagged_repo https://github.com/hyprwm/hyprgraphics.git \
        "${SRC_ROOT}/hyprgraphics" "$HYPRGRAPHICS_TAG"
    build_cmake_src "${SRC_ROOT}/hyprgraphics"

    ensure_tagged_repo https://github.com/hyprwm/hyprcursor.git \
        "${SRC_ROOT}/hyprcursor" "$HYPRCURSOR_TAG"
    build_cmake_src "${SRC_ROOT}/hyprcursor"

    ensure_tagged_repo https://github.com/hyprwm/hyprland-protocols.git \
        "${SRC_ROOT}/hyprland-protocols" "$HYPRLAND_PROTOCOLS_TAG"
    build_meson_src "${SRC_ROOT}/hyprland-protocols"

    ensure_tagged_repo https://github.com/hyprwm/aquamarine.git \
        "${SRC_ROOT}/aquamarine" "$AQUAMARINE_TAG"
    build_cmake_src "${SRC_ROOT}/aquamarine"

    ensure_tagged_repo https://github.com/hyprwm/hyprwire.git \
        "${SRC_ROOT}/hyprwire" "$HYPRWIRE_TAG"
    build_cmake_src "${SRC_ROOT}/hyprwire"

    ensure_tagged_repo https://github.com/hyprwm/hyprtoolkit.git \
        "${SRC_ROOT}/hyprtoolkit" "$HYPRTOOLKIT_TAG"
    build_cmake_src "${SRC_ROOT}/hyprtoolkit"

    ensure_hyprland_tarball
    build_cmake_src "${SRC_ROOT}/Hyprland" \
        -DNO_UWSM:STRING=true

    ensure_tagged_repo https://github.com/hyprwm/hyprland-qt-support.git \
        "${SRC_ROOT}/hyprland-qt-support" "$HYPRLAND_QT_SUPPORT_TAG"
    build_cmake_src "${SRC_ROOT}/hyprland-qt-support"

    ensure_tagged_repo https://github.com/hyprwm/hyprqt6engine.git \
        "${SRC_ROOT}/hyprqt6engine" "$HYPRQT6ENGINE_TAG"
    build_cmake_src "${SRC_ROOT}/hyprqt6engine"

    ensure_tagged_repo https://github.com/hyprwm/hyprland-guiutils.git \
        "${SRC_ROOT}/hyprland-guiutils" "$HYPRLAND_GUIUTILS_TAG"
    build_cmake_src "${SRC_ROOT}/hyprland-guiutils"

    ensure_tagged_repo https://github.com/hyprwm/hypridle.git \
        "${SRC_ROOT}/hypridle" "$HYPRIDLE_TAG"
    build_cmake_src "${SRC_ROOT}/hypridle"

    ensure_tagged_repo https://github.com/hyprwm/hyprlock.git \
        "${SRC_ROOT}/hyprlock" "$HYPRLOCK_TAG"
    build_cmake_src "${SRC_ROOT}/hyprlock"

    ensure_tagged_repo https://github.com/hyprwm/hyprpaper.git \
        "${SRC_ROOT}/hyprpaper" "$HYPRPAPER_TAG"
    build_cmake_src "${SRC_ROOT}/hyprpaper"

    ensure_tagged_repo https://github.com/hyprwm/hyprpicker.git \
        "${SRC_ROOT}/hyprpicker" "$HYPRPICKER_TAG"
    build_cmake_src "${SRC_ROOT}/hyprpicker"

    ensure_tagged_repo https://github.com/hyprwm/hyprpolkitagent.git \
        "${SRC_ROOT}/hyprpolkitagent" "$HYPRPOLKITAGENT_TAG"
    build_cmake_src "${SRC_ROOT}/hyprpolkitagent"

    ensure_tagged_repo https://github.com/hyprwm/hyprlauncher.git \
        "${SRC_ROOT}/hyprlauncher" "$HYPRLAUNCHER_TAG"
    build_cmake_src "${SRC_ROOT}/hyprlauncher"

    ensure_tagged_repo https://github.com/hyprwm/hyprpwcenter.git \
        "${SRC_ROOT}/hyprpwcenter" "$HYPRPWCENTER_TAG"
    build_cmake_src "${SRC_ROOT}/hyprpwcenter"

    ensure_tagged_repo https://github.com/hyprwm/hyprsunset.git \
        "${SRC_ROOT}/hyprsunset" "$HYPRSUNSET_TAG"
    build_cmake_src "${SRC_ROOT}/hyprsunset"

    ensure_tagged_repo https://github.com/hyprwm/hyprsysteminfo.git \
        "${SRC_ROOT}/hyprsysteminfo" "$HYPRSYSTEMINFO_TAG"
    build_cmake_src "${SRC_ROOT}/hyprsysteminfo"

    ensure_tagged_repo https://github.com/hyprwm/hyprshutdown.git \
        "${SRC_ROOT}/hyprshutdown" "$HYPRSHUTDOWN_TAG"
    build_cmake_src "${SRC_ROOT}/hyprshutdown"

    ensure_tagged_repo https://github.com/hyprwm/xdg-desktop-portal-hyprland.git \
        "${SRC_ROOT}/xdg-desktop-portal-hyprland" "$XDPH_TAG"
    build_cmake_src "${SRC_ROOT}/xdg-desktop-portal-hyprland"
}

write_stamp() {
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        return 0
    fi
    sudo mkdir -p "$(dirname "$STAMP")"
    stamp_payload | sudo tee "$STAMP" >/dev/null
}

if [[ -x "${PREFIX}/bin/Hyprland" && -f "$STAMP" ]] \
    && [[ "$(cat "$STAMP")" == "$(stamp_payload)" ]] \
    && [[ "${HYPRLAND_SOURCE_FORCE:-0}" != "1" ]]; then
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
    log "installed ${HYPRLAND_TAG} to ${PREFIX} (Ly session: Hyprland (source 0.56.2))"
else
    die "build finished but ${PREFIX}/bin/Hyprland is missing"
fi
