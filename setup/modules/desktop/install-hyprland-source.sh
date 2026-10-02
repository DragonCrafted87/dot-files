#!/usr/bin/env bash
# Build the pinned Hyprland tag plus the hypr* ecosystem into /usr/local.
# Tags live in setup/versions.conf. Skip the whole install while the
# distro hyprland rpm is still present (role reset is what removes it).

set -euo pipefail
# shellcheck disable=SC1091
. "${REPO_ROOT:-$DOTFILES_ROOT}/setup/lib/lib.sh"

require_user

HYPRLAND_TAG="${HYPRLAND_TAG:?set HYPRLAND_TAG in setup/versions.conf}"
HYPRLAND_SOURCE_VERSION="${HYPRLAND_SOURCE_VERSION:-${HYPRLAND_TAG#v}}"
PREFIX="${HYPRLAND_SOURCE_PREFIX:-/usr/local}"
HYPRLAND_PATCH_CXX23="${HYPRLAND_PATCH_CXX23:-0}"
HYPRLAND_PATCH_STRING_CONCAT="${HYPRLAND_PATCH_STRING_CONCAT:-1}"
HYPRLAND_DISABLE_PCH="${HYPRLAND_DISABLE_PCH:-0}"
SRC_ROOT="${HYPRLAND_SOURCE_SRC:-${DOTFILES_HOME}/.cache/hyprland-source}"
STAMP="${PREFIX}/share/hyprland-source/.dotfiles-stamp"
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
GLAZE_TAG="${GLAZE_TAG:?set GLAZE_TAG in setup/versions.conf}"
HYPRCAPTURE_REV="${HYPRCAPTURE_REV:?set HYPRCAPTURE_REV in setup/versions.conf}"
HYPRCAPTURE_STAMP="${PREFIX}/share/hyprland-source/.hyprcapture-stamp"

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
glaze=${GLAZE_TAG}
prefix=${PREFIX}
stdlib=libstdc++
compiler=gcc
EOF
}

install_build_deps() {
    local pkgs=() picked group
    local groups=(
        "gcc-c++ gcc-c++-14 gcc" "glibc-devel" "mold" "atomic-devel libatomic-devel"
        "cmake" "meson" "ninja ninja-build" "make" "git"
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
        "lib64Qt6Quick-devel qt6-qtquick-devel"
        "lib64Qt6QuickControls2-devel qt6-qtquickcontrols2-devel"
        "lib64qalculate-devel qalculate-devel libqalculate-devel"
        "lib64pci-devel pciutils-devel libpci-devel"
        "lib64Qt6WaylandClient-devel lib64Qt6Wayland-devel qt6-qtwayland-devel lib64qt6wayland-devel"
        "qt6-qttools-devel lib64Qt6Tools-devel"
        "automake autoconf libtool xorg-x11-util-macros util-macros"
        "lib64iniparser-devel iniparser-devel"
    )
    for group in "${groups[@]}"; do
        # shellcheck disable=SC2086
        if picked="$(pick_pkg $group)"; then pkgs+=("$picked"); else warn "no package matched: $group"; fi
    done
    [[ "${#pkgs[@]}" -gt 0 ]] && ensure_packages "${pkgs[@]}"
}

# OpenMandriva cooker builds Hyprland 0.56.2 with GCC. Clang 19 is known
# to crash the compositor at launch (aquamarine.spec) and dies on glaze
# reflection during compile. compiler.bashrc prefers LLVM; override here.
strip_flag_from() {
    local varname="$1" flag="$2" tok
    local -a toks=()
    local val="${!varname:-}"
    for tok in $val; do
        [[ "$tok" == "$flag" ]] && continue
        toks+=("$tok")
    done
    printf -v "$varname" '%s' "${toks[*]}"
}

use_hyprland_gcc() {
    export CC=gcc
    export CXX=g++
    export CMAKE_C_COMPILER=gcc
    export CMAKE_CXX_COMPILER=g++
    local concat_shim="${SETUP_FILES_DIR}/hyprland-source/string_view_concat.hpp"
    if [[ -f "$concat_shim" ]]; then
        case " ${CXXFLAGS:-} " in
            *" -include ${concat_shim} "*) ;;
            *) CXXFLAGS="${CXXFLAGS:+${CXXFLAGS} }-include ${concat_shim}" ;;
        esac
    fi
    unset CMAKE_AR CMAKE_RANLIB AR RANLIB NM
    command -v gcc-ar >/dev/null 2>&1 && export AR=gcc-ar
    command -v gcc-ranlib >/dev/null 2>&1 && export RANLIB=gcc-ranlib

    strip_flag_from CXXFLAGS -stdlib=libc++
    strip_flag_from LDFLAGS -stdlib=libc++
    strip_flag_from LDFLAGS -fuse-ld=lld
    strip_flag_from CFLAGS -fuse-ld=lld
    if command -v mold >/dev/null 2>&1; then
        case " ${LDFLAGS:-} " in *" -fuse-ld=mold "*) ;; *) LDFLAGS="${LDFLAGS:+${LDFLAGS} }-fuse-ld=mold" ;; esac
        export LD=mold
    fi
    export CFLAGS CXXFLAGS LDFLAGS
}

export_prefix_env() {
    use_hyprland_gcc
    export PATH="${PREFIX}/bin:${PATH:-/usr/bin}"
    export PKG_CONFIG_PATH="${PREFIX}/lib64/pkgconfig:${PREFIX}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
    export CMAKE_PREFIX_PATH="${PREFIX}${CMAKE_PREFIX_PATH:+:${CMAKE_PREFIX_PATH}}"
    export LD_LIBRARY_PATH="${PREFIX}/lib64:${PREFIX}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
    # rpath is runtime only. hyprland-qt-support links the bare name hyprlang,
    # and mold does not search PREFIX/lib64 unless gcc is given -L or LIBRARY_PATH.
    case ":${LIBRARY_PATH:-}:" in
        *":${PREFIX}/lib64:"*) ;;
        *) export LIBRARY_PATH="${PREFIX}/lib64:${PREFIX}/lib${LIBRARY_PATH:+:${LIBRARY_PATH}}" ;;
    esac
    case " ${LDFLAGS:-} " in
        *" -L${PREFIX}/lib64 "*) ;;
        *) LDFLAGS="${LDFLAGS:+${LDFLAGS} }-L${PREFIX}/lib64 -L${PREFIX}/lib" ;;
    esac
    case " ${LDFLAGS:-} " in
        *" -Wl,-rpath,${PREFIX}/lib64 "*) ;;
        *) LDFLAGS="${LDFLAGS:+${LDFLAGS} }-Wl,-rpath,${PREFIX}/lib64" ;;
    esac
    export LDFLAGS
}

# Role reset removes the distro package. Until that is gone, do not build
# and do not write /usr/local or /opt/hyprland.
skip_if_distro_hyprland() {
    local ver
    # rpm -q prints "package hyprland is not installed" on stdout and exits 1.
    # Gate on the status, not on whether that text is non-empty.
    ver="$(rpm -q hyprland 2>/dev/null)" || return 0
    log "skip Hyprland source: distro package still installed: ${ver}"
    exit 0
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
    git -C "$dir" checkout -f --detach "$ref" || git -C "$dir" checkout -f --detach "origin/${ref}"
    git -C "$dir" submodule update --init --recursive
}

patch_hyprland_python() {
    local f="${SRC_ROOT}/Hyprland/meta/generateLuaStubs.py"
    [[ -f "$f" ]] || return 0
    log "patch ${f} for pre-3.12 python"
    sed -i -E 's/^([ \t]*)type ([A-Za-z_][A-Za-z0-9_]*) = /\1\2 = /' "$f"
}

patch_hyprland_cxx23() {
    local f="${SRC_ROOT}/Hyprland/CMakeLists.txt"
    [[ -f "$f" ]] || return 0
    log "pin Hyprland CMAKE_CXX_STANDARD 23 (clang 19 + glaze)"
    [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && return 0
    sed -i -E 's/set\([[:space:]]*CMAKE_CXX_STANDARD[[:space:]]+26/set(CMAKE_CXX_STANDARD 23/' "$f"
}

patch_hyprland_string_concat() {
    local f="${SRC_ROOT}/Hyprland/hyprctl/src/main.cpp"
    [[ -f "$f" ]] || return 0
    log "patch ${f} string + string_view for C++23"
    [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && return 0
    sed -i -E 's/instanceSignature \+ "\/" \+ filename/instanceSignature + "\/" + std::string(filename)/' "$f"
}

# Rock libstdc++ has no std::ranges::starts_with. Lowercase + string::starts_with.
patch_hyprland_truthy() {
    local f="${SRC_ROOT}/Hyprland/src/helpers/MiscFunctions.cpp"
    [[ -f "$f" ]] || return 0
    grep -q 'std::ranges::starts_with' "$f" || return 0
    log "patch ${f} truthy() for GCC 14 ranges"
    [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && return 0
    python3 - "$f" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = '''bool truthy(const std::string& str) {
    using std::operator""sv;

    if (str == "1"sv)
        return true;

    // clang-format off
    auto str_view = str | std::views::transform([](unsigned char ch) -> char {
        return sc<char>(std::tolower(ch));
    });

    return [&](auto&&... prefixes) -> bool {
        return (... || std::ranges::starts_with(str_view, prefixes));
    }("true"sv, "yes"sv, "on"sv);
    // clang-format on
}'''
new = '''bool truthy(const std::string& str) {
    if (str == "1")
        return true;
    std::string lower(str.size(), '\\0');
    std::transform(str.begin(), str.end(), lower.begin(), [](unsigned char ch) -> char {
        return static_cast<char>(std::tolower(ch));
    });
    return lower.starts_with("true") || lower.starts_with("yes") || lower.starts_with("on");
}'''
if old not in text:
    raise SystemExit("MiscFunctions.cpp truthy() block not found")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
PY
}

# pkg_check_modules(tomlplusplus hyprutils) puts -L/usr/lib64 first, so cmake
# find_library picks Rock hyprutils 0.6 instead of the prefix 0.14.2.
patch_hyprland_hyprpm_pkgconfig() {
    local f="${SRC_ROOT}/Hyprland/hyprpm/CMakeLists.txt"
    [[ -f "$f" ]] || return 0
    grep -q 'tomlplusplus hyprutils' "$f" || return 0
    log "patch ${f} pkg-config order so prefix hyprutils wins"
    [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && return 0
    sed -i -E 's/tomlplusplus hyprutils>=0\.7\.0/hyprutils>=0.7.0 tomlplusplus/' "$f"
}

# OpenMandriva pci.h has no extern "C", so C++ TUs mangle pci_alloc.
patch_pci_extern_c() {
    local root="$1" f
    [[ -d "$root" ]] || return 0
    while IFS= read -r f; do
        grep -q '#include <pci/pci.h>' "$f" || continue
        grep -q 'extern "C"' "$f" && continue
        log "wrap pci.h in extern C in ${f}"
        [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && continue
        sed -i 's|#include <pci/pci.h>|extern "C" {\n#include <pci/pci.h>\n}|' "$f"
    done < <(find "$root" \( -name '*.cpp' -o -name '*.hpp' -o -name '*.h' \) ! -path '*/build/*')
}

# GCC 14 has no #embed; expand quoted #embed "path" into byte lists.
rewrite_embed_tree() {
    local root="$1"
    [[ -d "$root" ]] || return 0
    [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && { log "would expand #embed in ${root}"; return 0; }
    python3 - "$root" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
embed = re.compile(r"^#embed\s+\"([^\"]+)\"\s*$", re.M)

for path in root.rglob("*"):
    if path.suffix not in {".c", ".cc", ".cpp", ".cxx", ".h", ".hpp"}:
        continue
    if "build" in path.parts:
        continue
    text = path.read_text(encoding="utf-8", errors="replace")
    if "#embed" not in text:
        continue

    def repl(match: re.Match[str]) -> str:
        target = (path.parent / match.group(1)).resolve()
        if not target.is_file():
            raise SystemExit(f"#embed missing file {target} from {path}")
        return ", ".join(str(b) for b in target.read_bytes())

    new, n = embed.subn(repl, text)
    if n:
        path.write_text(new, encoding="utf-8")
        print(f"expanded {n} #embed in {path}")
PY
}

# GCC 14 has no #embed; expand the default lua config into a byte array.
patch_hyprland_embed() {
    local hpp="${SRC_ROOT}/Hyprland/src/config/lua/DefaultConfig.hpp"
    local lua="${SRC_ROOT}/Hyprland/example/hyprland.lua"
    [[ -f "$hpp" && -f "$lua" ]] || return 0
    grep -q '^#embed ' "$hpp" || return 0
    log "expand #embed in ${hpp} for GCC 14"
    [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && return 0
    python3 - "$hpp" "$lua" <<'PY'
from pathlib import Path
import sys

hpp = Path(sys.argv[1])
lua = Path(sys.argv[2])
text = hpp.read_text(encoding="utf-8")
marker = "#embed"
if marker not in text:
    raise SystemExit(0)
bytes_list = ", ".join(str(b) for b in lua.read_bytes())
old = """inline constexpr char             EXAMPLE_CONFIG_BYTES_LUA[] = {
#embed "../../../example/hyprland.lua"
};"""
new = "inline constexpr char             EXAMPLE_CONFIG_BYTES_LUA[] = {" + bytes_list + "};"
if old not in text:
    raise SystemExit("DefaultConfig.hpp #embed block not found")
hpp.write_text(text.replace(old, new, 1), encoding="utf-8")
PY
}

# GCC rejects ternary CXCBConnection vs nullptr; clang converts via operator xcb_connection_t*().
patch_hyprland_xcb_ternary() {
    local f="${SRC_ROOT}/Hyprland/src/xwayland/XWM.hpp"
    [[ -f "$f" ]] || return 0
    grep -q 'm_connection ? \*m_connection : nullptr' "$f" || return 0
    log "patch ${f} GCC xcb connection ternary"
    [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && return 0
    python3 - "$f" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = "return m_connection ? *m_connection : nullptr;"
new = "if (!m_connection)\n            return nullptr;\n        return *m_connection;"
if old not in text:
    raise SystemExit(0)
path.write_text(text.replace(old, new, 1), encoding="utf-8")
PY
}

apply_hyprland_source_patches() {
    patch_hyprland_python
    patch_hyprland_glaze
    rewrite_append_range_tree "${SRC_ROOT}/Hyprland"
    patch_hyprland_xcb_ternary
    patch_hyprland_embed
    patch_hyprland_truthy
    patch_hyprland_hyprpm_pkgconfig
    if [[ "${HYPRLAND_PATCH_CXX23}" == "1" ]]; then
        patch_hyprland_cxx23
    fi
    if [[ "${HYPRLAND_PATCH_STRING_CONCAT}" == "1" ]]; then
        patch_hyprland_string_concat
    fi
    return 0
}

ensure_hyprland_tarball() {
    local dest="${SRC_ROOT}/Hyprland"
    local tarball="${SRC_ROOT}/source-${HYPRLAND_TAG}.tar.gz"
    local url="https://github.com/hyprwm/Hyprland/releases/download/${HYPRLAND_TAG}/source-${HYPRLAND_TAG}.tar.gz"
    if [[ -d "$dest" && -f "${dest}/CMakeLists.txt" ]]; then
        log "Hyprland sources already unpacked at ${dest}"
        apply_hyprland_source_patches
        return 0
    fi
    log "fetch Hyprland ${HYPRLAND_TAG} release tarball"
    [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && return 0
    ensure_dir "$SRC_ROOT"
    if command -v curl >/dev/null 2>&1; then curl -fsSL -o "$tarball" "$url"; else wget -q -O "$tarball" "$url"; fi
    rm -rf "$dest"
    mkdir -p "$dest"
    tar -xzf "$tarball" -C "$dest" --strip-components=1
    apply_hyprland_source_patches
}

cmake_config_flags=()
fill_cmake_config_flags() {
    use_hyprland_gcc
    CMAKE_EXE_LINKER_FLAGS="${LDFLAGS:-}"
    case " ${CMAKE_EXE_LINKER_FLAGS} " in *" --allow-shlib-undefined "*) ;; *) CMAKE_EXE_LINKER_FLAGS="${CMAKE_EXE_LINKER_FLAGS:+${CMAKE_EXE_LINKER_FLAGS} }-Wl,--allow-shlib-undefined" ;; esac
    cmake_config_flags=(
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_PREFIX_PATH="$PREFIX"
        -DCMAKE_LIBRARY_PATH="${PREFIX}/lib64;${PREFIX}/lib"
        -DCMAKE_INSTALL_LIBDIR=lib64 -DCMAKE_INSTALL_RPATH="${PREFIX}/lib64;${PREFIX}/lib"
        -DCMAKE_BUILD_RPATH="${PREFIX}/lib64;${PREFIX}/lib" -DBUILD_TESTING=OFF
        -DCMAKE_C_COMPILER="${CMAKE_C_COMPILER:-${CC:-gcc}}"
        -DCMAKE_CXX_COMPILER="${CMAKE_CXX_COMPILER:-${CXX:-g++}}"
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
        check-*|generate-lua-stubs|*lua-stub*|fuzz*|json_exhaustive*) return 0 ;;
        *aotstats*|all_aotstats) return 0 ;;
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

# Rock GCC 14 libstdc++ has no vector append_range/insert_range.
rewrite_append_range_tree() {
    local root="$1"
    [[ -d "$root" ]] || return 0
    [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && { log "would rewrite append_range in ${root}"; return 0; }
    python3 - "$root" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])


def walk_ident(text: str, j: int) -> str:
    k = j
    while k > 0 and (text[k - 1].isalnum() or text[k - 1] in "._"):
        k -= 1
    return text[k:j], k


def take_parens(text: str, p: int) -> tuple[str, int]:
    depth = 1
    start = p
    while p < len(text) and depth:
        if text[p] == "(":
            depth += 1
        elif text[p] == ")":
            depth -= 1
        p += 1
    return text[start : p - 1], p


def rewrite_append(text: str) -> tuple[str, int]:
    key = ".append_range("
    out: list[str] = []
    i = 0
    n = 0
    while True:
        j = text.find(key, i)
        if j < 0:
            out.append(text[i:])
            break
        obj, k = walk_ident(text, j)
        arg, p = take_parens(text, j + len(key))
        out.append(text[i:k])
        out.append(
            "{ auto&& _hypr_r = ("
            + arg
            + f"); {obj}.insert({obj}.end(), std::ranges::begin(_hypr_r), std::ranges::end(_hypr_r)); }}"
        )
        n += 1
        if p < len(text) and text[p] == ";":
            p += 1
        i = p
    return "".join(out), n


def rewrite_insert(text: str) -> tuple[str, int]:
    key = ".insert_range("
    out: list[str] = []
    i = 0
    n = 0
    while True:
        j = text.find(key, i)
        if j < 0:
            out.append(text[i:])
            break
        obj, k = walk_ident(text, j)
        args, p = take_parens(text, j + len(key))
        depth = 0
        comma = -1
        for idx, ch in enumerate(args):
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
            elif ch == "," and depth == 0:
                comma = idx
                break
        if comma < 0:
            out.append(text[i:p])
            i = p
            continue
        pos = args[:comma].strip()
        rng = args[comma + 1 :].strip()
        out.append(text[i:k])
        out.append(
            "{ auto&& _hypr_r = ("
            + rng
            + f"); {obj}.insert({pos}, std::ranges::begin(_hypr_r), std::ranges::end(_hypr_r)); }}"
        )
        n += 1
        if p < len(text) and text[p] == ";":
            p += 1
        i = p
    return "".join(out), n


for path in root.rglob("*"):
    if path.suffix not in {".c", ".cc", ".cpp", ".cxx", ".h", ".hpp"}:
        continue
    if "build" in path.parts:
        continue
    text = path.read_text(encoding="utf-8", errors="replace")
    if ".append_range(" not in text and ".insert_range(" not in text:
        continue
    new, n_append = rewrite_append(text)
    new, n_insert = rewrite_insert(new)
    n = n_append + n_insert
    if n == 0:
        continue
    if "#include <ranges>" not in new:
        new = re.sub(
            r"((?:^#include[^\n]*\n)+)",
            r"\1#include <ranges>\n",
            new,
            count=1,
            flags=re.M,
        )
    path.write_text(new, encoding="utf-8")
    print(f"patched {n_append} append_range {n_insert} insert_range in {path}")
PY
}

# libstdc++ std::format has no formatter for vector<string>.
patch_libstdcxx_format() {
    local f="${1}/src/core/Logger.hpp"
    [[ -f "$f" ]] || return 0
    grep -q 'formatter<std::vector<std::string>>' "$f" && return 0
    log "patch ${f} vector<string> formatter for libstdc++"
    [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && return 0
    python3 - "$f" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if "formatter<std::vector<std::string>>" in text:
    raise SystemExit(0)
snippet = """
#include <format>
#include <string>
#include <vector>

template <>
struct std::formatter<std::vector<std::string>> {
    constexpr auto parse(std::format_parse_context& ctx) { return ctx.begin(); }
    auto format(const std::vector<std::string>& values, std::format_context& ctx) const {
        auto out = ctx.out();
        *out++ = '[';
        bool first = true;
        for (const auto& value : values) {
            if (!first) {
                *out++ = ',';
                *out++ = ' ';
            }
            first = false;
            out = std::format_to(out, "{}", value);
        }
        *out++ = ']';
        return out;
    }
};

"""
idx = text.find("namespace Hyprtoolkit")
if idx < 0:
    raise SystemExit("Logger.hpp: missing Hyprtoolkit namespace")
path.write_text(text[:idx] + snippet + text[idx:], encoding="utf-8")
PY
}

build_cmake_src() {
    local src="$1"; shift || true
    local extra=("$@") jobs targets=() t build_args=()
    [[ -f "${src}/CMakeLists.txt" ]] || die "no CMakeLists.txt in ${src}"
    [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && { log "would cmake-build ${src} -> ${PREFIX}"; return 0; }
    rewrite_append_range_tree "$src"
    rewrite_embed_tree "$src"
    patch_libstdcxx_format "$src"
    patch_pci_extern_c "$src"
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
    rewrite_append_range_tree "$src"
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

tag_version() {
    local t="$1"
    printf '%s\n' "${t#v}"
}

prefix_has_pc() {
    local pc="$1" need="${2:-}" have
    [[ -f "${PREFIX}/lib64/pkgconfig/${pc}.pc" || -f "${PREFIX}/lib/pkgconfig/${pc}.pc" ]] || return 1
    [[ -z "$need" ]] && return 0
    have="$(PKG_CONFIG_PATH="${PREFIX}/lib64/pkgconfig:${PREFIX}/lib/pkgconfig" pkg-config --modversion "$pc" 2>/dev/null || true)"
    [[ -n "$have" ]] && pkg_ver_ge "$have" "$need"
}

should_build_component() {
    local name="$1"
    if [[ -n "${HYPRLAND_SOURCE_ONLY:-}" && "${HYPRLAND_SOURCE_ONLY}" != "$name" ]]; then
        log "skip ${name} (HYPRLAND_SOURCE_ONLY=${HYPRLAND_SOURCE_ONLY})"
        return 1
    fi
    return 0
}

build_tagged_cmake() {
    local name="$1" url="$2" dir="$3" tag="$4" pc="$5"
    shift 5 || true
    should_build_component "$name" || return 0
    if [[ "${HYPRLAND_SOURCE_FORCE:-0}" != "1" ]] && prefix_has_pc "$pc" "$(tag_version "$tag")"; then
        log "skip ${name}: prefix already has ${pc} $(tag_version "$tag")"
        return 0
    fi
    ensure_tagged_repo "$url" "$dir" "$tag"
    build_cmake_src "$dir" "$@"
}

build_tagged_meson() {
    local name="$1" url="$2" dir="$3" tag="$4" pc="$5"
    shift 5 || true
    should_build_component "$name" || return 0
    if [[ "${HYPRLAND_SOURCE_FORCE:-0}" != "1" ]] && prefix_has_pc "$pc" "$(tag_version "$tag")"; then
        log "skip ${name}: prefix already has ${pc} $(tag_version "$tag")"
        return 0
    fi
    ensure_tagged_repo "$url" "$dir" "$tag"
    build_meson_src "$dir" "$@"
}

build_prefixed_bin() {
    local name="$1" url="$2" dir="$3" tag="$4" bin="$5"
    shift 5 || true
    should_build_component "$name" || return 0
    if [[ "${HYPRLAND_SOURCE_FORCE:-0}" != "1" && -x "${PREFIX}/bin/${bin}" ]]; then
        log "skip ${name}: ${PREFIX}/bin/${bin} already installed"
        return 0
    fi
    ensure_tagged_repo "$url" "$dir" "$tag"
    build_cmake_src "$dir" "$@"
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

# libxkbcommon built with --prefix=/usr/local looks in
# /usr/local/share/X11/xkb. The xkeyboard-config files stay in
# /usr/share/X11/xkb; without this link Hyprland aborts in
# CKeybindManager::updateXKBTranslationState.
ensure_xkb_data() {
    local dest="${PREFIX}/share/X11/xkb" src="/usr/share/X11/xkb"
    [[ -d "$src" ]] || die "missing ${src}"
    if [[ -L "$dest" || -d "$dest" ]]; then
        return 0
    fi
    log "link ${src} -> ${dest}"
    [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && return 0
    sudo mkdir -p "$(dirname "$dest")"
    sudo ln -sfn "$src" "$dest"
}

ensure_libinput() {
    if ! ensure_pkg_or_build libinput 1.29; then return 0; fi
    ensure_tagged_repo https://gitlab.freedesktop.org/libinput/libinput.git "${SRC_ROOT}/libinput" "$LIBINPUT_TAG"
    build_meson_src "${SRC_ROOT}/libinput" -Dtests=false -Ddocumentation=false -Ddebug-gui=false -Dlibwacom=false
}

ensure_re2() {
    should_build_component re2 || return 0
    if [[ "${HYPRLAND_SOURCE_FORCE:-0}" != "1" ]] && prefix_has_pc re2; then
        log "skip re2: prefix already has re2"
        return 0
    fi
    ensure_tagged_repo https://github.com/google/re2.git "${SRC_ROOT}/re2" "$RE2_TAG"
    build_cmake_src "${SRC_ROOT}/re2" -DRE2_TEST=OFF -DRE2_BENCHMARK=OFF -DBUILD_SHARED_LIBS=ON
}

ensure_glaze() {
    local src="${SRC_ROOT}/glaze"
    should_build_component glaze || return 0
    if [[ "${HYPRLAND_SOURCE_FORCE:-0}" != "1" && -f "${PREFIX}/include/glaze/glaze.hpp" ]]; then
        log "skip glaze: prefix already has headers"
        return 0
    fi
    ensure_tagged_repo https://github.com/stephenberry/glaze.git "$src" "$GLAZE_TAG"
    [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && { log "would install glaze ${GLAZE_TAG} headers"; return 0; }
    rm -rf "${src}/build"
    fill_cmake_config_flags
    cmake -S "$src" -B "${src}/build" "${cmake_config_flags[@]}" -Dglaze_ENABLE_TESTING=OFF -DBUILD_TESTING=OFF
    sudo cmake --install "${src}/build"
}

patch_hyprland_glaze() {
    local root="${SRC_ROOT}/Hyprland" f
    [[ -d "$root" ]] || return 0
    log "pin glaze ${GLAZE_TAG} in Hyprland cmake (avoid FetchContent v7.2.0)"
    [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && return 0
    while IFS= read -r f; do
        sed -i -E "s/v7\\.2\\.0/${GLAZE_TAG}/g" "$f"
        sed -i -E 's/find_package\(glaze 7\.\.\.<8/find_package(glaze 8...<9/' "$f"
    done < <(find "$root" -name CMakeLists.txt)
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

install_local_lib_path() {
    local conf="/etc/ld.so.conf.d/hyprland-local.conf"
    [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && { log "would register ${PREFIX}/lib64 with ldconfig"; return 0; }
    printf '%s\n%s\n' "${PREFIX}/lib64" "${PREFIX}/lib" | sudo tee "$conf" >/dev/null
    sudo ldconfig
}

install_session_files() {
    local desktop_name="hyprland.desktop" tmp
    [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && { log "would install Ly session ${desktop_name}"; return 0; }
    tmp="$(mktemp)"
    cat >"$tmp" <<EOF
[Desktop Entry]
Name=Hyprland
Comment=Hyprland built into ${PREFIX}
Exec=${PREFIX}/bin/start-hyprland
TryExec=${PREFIX}/bin/start-hyprland
DesktopNames=Hyprland
Type=Application
EOF
    sudo install -d "$WAYLAND_SESSION_DIR"
    sudo install -m 0644 "$tmp" "${WAYLAND_SESSION_DIR}/${desktop_name}"
    rm -f "$tmp"
    # Ly lists custom_sessions in addition to /usr/share/wayland-sessions.
    # The same hyprland.desktop in both directories is two menu entries.
    sudo rm -f \
        "${WAYLAND_SESSION_DIR}/hyprland-source.desktop" \
        "${LY_CUSTOM_DIR}/hyprland-source.desktop" \
        "${LY_CUSTOM_DIR}/${desktop_name}"
    install_local_lib_path
}

install_prefix_desktops() {
    local name bin
    for name in hyprsysteminfo hyprpwcenter; do
        bin="${PREFIX}/bin/${name}"
        if [[ ! -x "$bin" ]]; then
            log "skip desktop ${name}: ${bin} missing"
            continue
        fi
        install_user_desktop "${SETUP_FILES_DIR}/applications/${name}.desktop"
    done
}

# Dropping hyprlauncher from the stamp must not rebuild the rest of the prefix.
reconcile_dropped_hyprlauncher_stamp() {
    local current trimmed
    [[ "${HYPRLAND_SOURCE_FORCE:-0}" == "1" ]] && return 0
    [[ -f "$STAMP" && -x "${PREFIX}/bin/Hyprland" ]] || return 0
    current="$(cat "$STAMP")"
    [[ "$current" == "$(stamp_payload)" ]] && return 0
    trimmed="$(grep -v '^hyprlauncher=' "$STAMP" || true)"
    [[ "$trimmed" == "$(stamp_payload)" ]] || return 0
    log "stamp only dropped hyprlauncher; rewriting without a prefix rebuild"
    write_stamp
    if [[ -e "${PREFIX}/bin/hyprlauncher" ]]; then
        log "remove ${PREFIX}/bin/hyprlauncher"
        [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] || sudo rm -f "${PREFIX}/bin/hyprlauncher"
    fi
}

ensure_hyprcapture_deps() {
    local pkgs=() picked group
    local groups=(
        "nlohmann_json-devel nlohmann-json-devel"
        "lib64LayerShellQtInterface6-devel lib64LayerShellQtInterface-devel"
        "lib64ffmpeg-devel ffmpeg-devel"
        "lib64fftw-devel fftw-devel"
        "lib64pulseaudio-devel libpulse-devel pulseaudio-libs-devel"
        "lib64Qt6Svg-devel qt6-qtsvg-devel"
        "lib64Qt6DBus-devel qt6-qtdbus-devel"
        "lib64Qt6Network-devel qt6-qtnetwork-devel"
        "gpu-screen-recorder"
        "ffmpeg"
    )
    for group in "${groups[@]}"; do
        # shellcheck disable=SC2086
        if picked="$(pick_pkg $group)"; then pkgs+=("$picked"); else warn "no package matched: $group"; fi
    done
    [[ "${#pkgs[@]}" -gt 0 ]] && ensure_packages "${pkgs[@]}"
}

# OpenMandriva ships plasma6-layer-shell-qt 6.3. HyprCapture calls the 6.6
# Window methods (setScreen, setDesiredSize, setActivateOnShow). QWindow::setScreen
# is already set, and ScreenFromQWindow is the 6.3 way to follow that screen.
patch_hyprcapture_layershell() {
    local root="$1"
    [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && return 0
    python3 - "$root" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
replacements = {
    "    if (auto* layerWindow = LayerShellQt::Window::get(windowHandle()))\n        layerWindow->setDesiredSize(size());\n": "",
    "layerWindow->setScreen(screen);": "layerWindow->setScreenConfiguration(LayerShellQt::Window::ScreenFromQWindow);",
    "layerWindow->setScreen(targetScreen);": "layerWindow->setScreenConfiguration(LayerShellQt::Window::ScreenFromQWindow);",
    "layerWindow->setActivateOnShow(false);": "",
    "layerWindow->setActivateOnShow(true);": "",
    "layerWindow->setDesiredSize(QSize(0, 0));": "",
    "layerWindow->setDesiredSize(size());": "",
    "#if LAYERSHELLQTINTERFACE_ENABLE_DEPRECATED_SINCE(6, 6)": "#if 1",
}
for path in root.rglob("*.cpp"):
    text = path.read_text(encoding="utf-8")
    updated = text
    for old, new in replacements.items():
        updated = updated.replace(old, new)
    if updated != text:
        path.write_text(updated, encoding="utf-8")
PY
}

ensure_hyprcapture() {
    local dir="${SRC_ROOT}/HyprCapture"
    local so ui built_so built_ui
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        log "would build hyprcapture into ${PREFIX}"
        return 0
    fi
    should_build_component hyprcapture || return 0
    so="${PREFIX}/lib/libhyprcapture.so"
    ui="${PREFIX}/bin/hyprcapture-ui"
    if [[ "${HYPRLAND_SOURCE_FORCE:-0}" != "1" && -f "$HYPRCAPTURE_STAMP" ]] \
        && [[ "$(cat "$HYPRCAPTURE_STAMP")" == "$HYPRCAPTURE_REV" ]] \
        && [[ -f "$so" && -x "$ui" ]]; then
        log "hyprcapture ${HYPRCAPTURE_REV} already installed"
        return 0
    fi
    if [[ ! -f "${SRC_ROOT}/Hyprland/src/plugins/PluginAPI.hpp" ]]; then
        ensure_hyprland_tarball
    fi
    [[ -f "${SRC_ROOT}/Hyprland/src/plugins/PluginAPI.hpp" ]] \
        || die "Hyprland sources missing; cannot build HyprCapture"
    ensure_hyprcapture_deps
    export_prefix_env
    ensure_tagged_repo https://github.com/gfhdhytghd/HyprCapture.git "$dir" "$HYPRCAPTURE_REV"
    # The echo-cancel helper is a separate static library and is not installed.
    [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && { log "would cmake-build hyprcapture"; return 0; }
    rewrite_append_range_tree "$dir"
    patch_hyprcapture_layershell "$dir"
    rm -rf "${dir}/build"
    fill_cmake_config_flags
    cmake -S "$dir" -B "${dir}/build" "${cmake_config_flags[@]}" \
        -DHYPRLAND_SOURCE_DIR="${SRC_ROOT}/Hyprland" \
        -DHYPRCAPTURE_DEFAULT_HELPER_PATH="${ui}"
    cmake --build "${dir}/build" --config Release -j"$(nproc)" \
        --target hyprcapture --target hyprcapture-ui
    built_so="$(find "${dir}/build" -name 'libhyprcapture.so' -type f -print -quit)"
    built_ui="${dir}/build/hyprcapture-ui"
    [[ -n "$built_so" && -f "$built_so" ]] || die "HyprCapture build did not produce libhyprcapture.so"
    [[ -x "$built_ui" ]] || die "HyprCapture build did not produce hyprcapture-ui"
    sudo install -d "${PREFIX}/lib" "${PREFIX}/bin"
    sudo install -m 0755 "$built_so" "$so"
    sudo install -m 0755 "$built_ui" "$ui"
    sudo mkdir -p "$(dirname "$HYPRCAPTURE_STAMP")"
    printf '%s\n' "$HYPRCAPTURE_REV" | sudo tee "$HYPRCAPTURE_STAMP" >/dev/null
    log "installed hyprcapture ${HYPRCAPTURE_REV}"
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
    build_tagged_cmake hyprwayland-scanner https://github.com/hyprwm/hyprwayland-scanner.git \
        "${SRC_ROOT}/hyprwayland-scanner" "$HYPRWAYLAND_SCANNER_TAG" hyprwayland-scanner
    build_tagged_cmake hyprutils https://github.com/hyprwm/hyprutils.git \
        "${SRC_ROOT}/hyprutils" "$HYPRUTILS_TAG" hyprutils
    build_tagged_cmake hyprlang https://github.com/hyprwm/hyprlang.git \
        "${SRC_ROOT}/hyprlang" "$HYPRLANG_TAG" hyprlang
    build_tagged_cmake hyprgraphics https://github.com/hyprwm/hyprgraphics.git \
        "${SRC_ROOT}/hyprgraphics" "$HYPRGRAPHICS_TAG" hyprgraphics
    build_tagged_cmake hyprcursor https://github.com/hyprwm/hyprcursor.git \
        "${SRC_ROOT}/hyprcursor" "$HYPRCURSOR_TAG" hyprcursor
    build_tagged_meson hyprland-protocols https://github.com/hyprwm/hyprland-protocols.git \
        "${SRC_ROOT}/hyprland-protocols" "$HYPRLAND_PROTOCOLS_TAG" hyprland-protocols
    build_tagged_cmake aquamarine https://github.com/hyprwm/aquamarine.git \
        "${SRC_ROOT}/aquamarine" "$AQUAMARINE_TAG" aquamarine
    build_tagged_cmake hyprwire https://github.com/hyprwm/hyprwire.git \
        "${SRC_ROOT}/hyprwire" "$HYPRWIRE_TAG" hyprwire
    build_tagged_cmake hyprtoolkit https://github.com/hyprwm/hyprtoolkit.git \
        "${SRC_ROOT}/hyprtoolkit" "$HYPRTOOLKIT_TAG" hyprtoolkit
    ensure_wayland_protocols
    ensure_libxkbcommon
    ensure_xkb_data
    ensure_libinput
    ensure_re2
    ensure_glaze
    if should_build_component Hyprland; then
        if [[ "${HYPRLAND_SOURCE_FORCE:-0}" != "1" && -x "${PREFIX}/bin/Hyprland" ]]; then
            log "skip Hyprland: ${PREFIX}/bin/Hyprland already installed"
        else
            ensure_hyprland_tarball
            hyprland_cmake_extra=(-DNO_UWSM:STRING=true)
            if [[ "${HYPRLAND_DISABLE_PCH}" == "1" ]]; then
                hyprland_cmake_extra+=(-DCMAKE_DISABLE_PRECOMPILE_HEADERS=ON)
            fi
            build_cmake_src "${SRC_ROOT}/Hyprland" "${hyprland_cmake_extra[@]}"
        fi
    fi
    build_tagged_cmake hyprland-qt-support https://github.com/hyprwm/hyprland-qt-support.git \
        "${SRC_ROOT}/hyprland-qt-support" "$HYPRLAND_QT_SUPPORT_TAG" hyprland-qt-support
    build_tagged_cmake hyprqt6engine https://github.com/hyprwm/hyprqt6engine.git \
        "${SRC_ROOT}/hyprqt6engine" "$HYPRQT6ENGINE_TAG" hyprqt6engine
    build_prefixed_bin hyprland-guiutils https://github.com/hyprwm/hyprland-guiutils.git \
        "${SRC_ROOT}/hyprland-guiutils" "$HYPRLAND_GUIUTILS_TAG" hyprland-welcome
    build_prefixed_bin hypridle https://github.com/hyprwm/hypridle.git \
        "${SRC_ROOT}/hypridle" "$HYPRIDLE_TAG" hypridle
    build_prefixed_bin hyprlock https://github.com/hyprwm/hyprlock.git \
        "${SRC_ROOT}/hyprlock" "$HYPRLOCK_TAG" hyprlock
    build_prefixed_bin hyprpaper https://github.com/hyprwm/hyprpaper.git \
        "${SRC_ROOT}/hyprpaper" "$HYPRPAPER_TAG" hyprpaper
    build_prefixed_bin hyprpicker https://github.com/hyprwm/hyprpicker.git \
        "${SRC_ROOT}/hyprpicker" "$HYPRPICKER_TAG" hyprpicker
    build_prefixed_bin hyprpolkitagent https://github.com/hyprwm/hyprpolkitagent.git \
        "${SRC_ROOT}/hyprpolkitagent" "$HYPRPOLKITAGENT_TAG" hyprpolkitagent
    build_prefixed_bin hyprpwcenter https://github.com/hyprwm/hyprpwcenter.git \
        "${SRC_ROOT}/hyprpwcenter" "$HYPRPWCENTER_TAG" hyprpwcenter
    build_prefixed_bin hyprsunset https://github.com/hyprwm/hyprsunset.git \
        "${SRC_ROOT}/hyprsunset" "$HYPRSUNSET_TAG" hyprsunset
    build_prefixed_bin hyprsysteminfo https://github.com/hyprwm/hyprsysteminfo.git \
        "${SRC_ROOT}/hyprsysteminfo" "$HYPRSYSTEMINFO_TAG" hyprsysteminfo
    build_prefixed_bin hyprshutdown https://github.com/hyprwm/hyprshutdown.git \
        "${SRC_ROOT}/hyprshutdown" "$HYPRSHUTDOWN_TAG" hyprshutdown
    build_prefixed_bin xdg-desktop-portal-hyprland https://github.com/hyprwm/xdg-desktop-portal-hyprland.git \
        "${SRC_ROOT}/xdg-desktop-portal-hyprland" "$XDPH_TAG" xdg-desktop-portal-hyprland
}

write_stamp() {
    [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && return 0
    sudo mkdir -p "$(dirname "$STAMP")"
    stamp_payload | sudo tee "$STAMP" >/dev/null
}

skip_if_distro_hyprland
reconcile_dropped_hyprlauncher_stamp

if [[ -x "${PREFIX}/bin/Hyprland" && -f "$STAMP" ]] && [[ "$(cat "$STAMP")" == "$(stamp_payload)" ]] && [[ "${HYPRLAND_SOURCE_FORCE:-0}" != "1" ]]; then
    log "Hyprland ${HYPRLAND_SOURCE_VERSION} prefix already current at ${PREFIX}"
    ensure_xkb_data
    install_session_files
    install_prefix_desktops
    ensure_hyprcapture
    configure_ly_source_session
    exit 0
fi

install_build_deps
if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
    log "would build Hyprland ${HYPRLAND_TAG} and ecosystem into ${PREFIX}"
    install_session_files
    install_prefix_desktops
    ensure_hyprcapture
    configure_ly_source_session
    exit 0
fi

command -v gcc >/dev/null 2>&1 || die "gcc is not on PATH after package install"
command -v g++ >/dev/null 2>&1 || die "g++ is not on PATH after package install"
command -v mold >/dev/null 2>&1 || die "mold is not on PATH after package install"
command -v cmake >/dev/null 2>&1 || die "cmake is not on PATH after package install"
command -v meson >/dev/null 2>&1 || die "meson is not on PATH after package install"
command -v make >/dev/null 2>&1 || die "make is not on PATH after package install"

build_stack
install_session_files
install_prefix_desktops
ensure_hyprcapture
configure_ly_source_session
write_stamp

if [[ -x "${PREFIX}/bin/Hyprland" ]]; then
    log "installed ${HYPRLAND_TAG} to ${PREFIX} (Ly session: Hyprland)"
else
    die "build finished but ${PREFIX}/bin/Hyprland is missing"
fi
