#!/usr/bin/env bash
# Build BOINC client + manager from the tagged GitHub source.
# OpenMandriva has no working BOINC rpms; Fedora packages ABI-mismatch.
# Version comes from setup/versions.conf so a role rerun skips the compile
# when the stamp matches.

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
        "git"
        "clang"
        "llvm"
        "lld"
        "gcc"
        "gcc-c++ gcc-c++-znver1 gcc-c++-x86_64"
        "glibc-devel lib64c-devel"
        "lib64stdc++-devel libstdc++-devel"
        "make"
        "autoconf"
        "automake"
        "libtool"
        "pkgconf pkgconfig"
        "m4"
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
        ./configure \
            --prefix="$BOINC_PREFIX" \
            --disable-server \
            --disable-fcgi \
            --disable-silent-rules \
            --enable-unicode \
            --with-ssl \
            --with-x \
            CC="${CC:-clang}" \
            CXX="${CXX:-clang++}" \
            CFLAGS="${CFLAGS:-}" \
            CXXFLAGS="${CXXFLAGS:-}"
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
            run sudo flatpak uninstall -y edu.berkeley.BOINC || \
                run flatpak uninstall -y edu.berkeley.BOINC || true
        fi
    fi
    if [[ -f /etc/yum.repos.d/boinc-stable.repo ]]; then
        log "remove leftover BOINC distro repo"
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
        if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
            return 0
        fi
        mv "$OLD_DATA_DIR" "$BOINC_DIR"
        return 0
    fi
    ensure_dir "$BOINC_DIR"
}

remove_stale_path_cmds() {
    local stale
    for stale in find-boinccmd.sh find-boinccmd \
        boinc-session.sh boinc-session \
        boinc-config.sh boinc-status.sh boinc-status-all.sh; do
        if [[ -e "/usr/local/bin/${stale}" ]]; then
            log "remove /usr/local/bin/${stale}"
            run sudo rm -f "/usr/local/bin/${stale}"
        fi
    done
}

remove_flatpak_boinc

if systemctl --user list-unit-files boinc-client.service >/dev/null 2>&1; then
    if systemctl --user is-active --quiet boinc-client.service; then
        log "stop user boinc-client before rebuild"
        run systemctl --user stop boinc-client.service || true
    fi
fi
if systemctl list-unit-files boinc-client.service >/dev/null 2>&1; then
    disable_service boinc-client.service || true
fi

if boinc_already_built; then
    log "BOINC ${BOINC_VERSION} already installed"
else
    build_boinc
fi

migrate_data_dir
remove_stale_path_cmds

rpc_file="${BOINC_DIR}/gui_rpc_auth.cfg"
secret="${DOTFILES_HOME}/.config/dot-files/boinc-rpc.password"
src="${SETUP_FILES_DIR}/boinc"
prefs_dir="${src}/prefs"
role="${OMV_ROLE:-}"
if [[ -z "$role" && -f "${CONFIG_TARGET_DIR}/dot-files/role" ]]; then
    role="$(tr -d '[:space:]' <"${CONFIG_TARGET_DIR}/dot-files/role")"
fi
role="${role:-server}"
prefs_src="${prefs_dir}/${role}.xml"
[[ -f "$prefs_src" ]] || die "missing role prefs ${prefs_src}"

hosts_list="${src}/hosts.list"
short_host="$(hostname -s 2>/dev/null || hostname)"
short_host="${short_host%%.*}"

boinc_role_header() {
    case "$1" in
        workstation) printf '%s\n' '# workstation' ;;
        laptop) printf '%s\n' '# laptop' ;;
        htpc) printf '%s\n' '# htpcs' ;;
        server) printf '%s\n' '# servers' ;;
        *) printf '# %s\n' "$1" ;;
    esac
}

host_in_list() {
    local list="$1" name="$2" line stripped
    [[ -f "$list" ]] || return 1
    while IFS= read -r line || [[ -n "${line:-}" ]]; do
        stripped="${line%%#*}"
        stripped="${stripped//[[:space:]]/}"
        [[ -z "$stripped" ]] && continue
        stripped="${stripped%%.*}"
        if [[ "$stripped" == "$name" ]]; then
            return 0
        fi
    done <"$list"
    return 1
}

ensure_host_in_list() {
    local list="$1" name="$2" header="$3"
    local tmp line inserted=0
    if host_in_list "$list" "$name"; then
        return 0
    fi
    log "add ${name} to hosts.list under ${header}"
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        return 0
    fi
    tmp="$(mktemp)"
    if [[ -f "$list" ]]; then
        while IFS= read -r line || [[ -n "${line:-}" ]]; do
            printf '%s\n' "$line" >>"$tmp"
            if [[ "$line" == "$header" ]]; then
                printf '%s\n' "$name" >>"$tmp"
                inserted=1
            fi
        done <"$list"
    fi
    if [[ "$inserted" -eq 0 ]]; then
        printf '\n%s\n%s\n' "$header" "$name" >>"$tmp"
    fi
    cat "$tmp" >"$list"
    rm -f "$tmp"
}

ensure_host_in_list "$hosts_list" "$short_host" "$(boinc_role_header "$role")"

if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
    log "configure ${BOINC_DIR} from ${src} (prefs ${role})"
    exit 0
fi

ensure_dir "$BOINC_DIR"
ensure_dir "${DOTFILES_HOME}/.config/systemd/user"
ensure_dir /etc/boinc-client || run sudo mkdir -p /etc/boinc-client

install -m 0644 "${src}/boinc-client.service" \
    "${DOTFILES_HOME}/.config/systemd/user/boinc-client.service"

boinc_changed=0
install_boinc_file() {
    local from="$1"
    local to="$2"
    local mode="${3:-0644}"
    local as_root="${4:-0}"
    if [[ -f "$to" ]] && cmp -s "$from" "$to"; then
        return 0
    fi
    log "update ${to}"
    if [[ "$as_root" == "1" ]]; then
        sudo install -m "$mode" "$from" "$to"
    else
        install -m "$mode" "$from" "$to"
    fi
    boinc_changed=1
}

ensure_dir "${DOTFILES_HOME}/.config/dot-files"
rpc_password=""
science_united_user=""
science_united_password=""
if [[ -f "$secret" ]]; then
    if grep -q '=' "$secret"; then
        while IFS='=' read -r key value || [[ -n "${key:-}" ]]; do
            [[ -z "$key" || "$key" == \#* ]] && continue
            key="${key%"${key##*[![:space:]]}"}"
            value="${value%"${value##*[![:space:]]}"}"
            value="${value#"${value%%[![:space:]]*}"}"
            case "$key" in
                rpc_password) rpc_password="$value" ;;
                science_united_user) science_united_user="$value" ;;
                science_united_password) science_united_password="$value" ;;
            esac
        done <"$secret"
    else
        rpc_password="$(tr -d '[:space:]' <"$secret")"
    fi
fi
if [[ -z "$rpc_password" && -f "$rpc_file" ]]; then
    rpc_password="$(tr -d '[:space:]' <"$rpc_file")"
fi
if [[ -z "$rpc_password" ]]; then
    rpc_password="$(head -c 32 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 32)"
    warn "generated rpc_password in ${secret}; copy that file to the other boxes"
fi
umask 077
cat >"$secret" <<EOF
rpc_password=${rpc_password}
science_united_user=${science_united_user}
science_united_password=${science_united_password}
EOF
chmod 600 "$secret"
if [[ -z "$science_united_user" || -z "$science_united_password" ]]; then
    warn "add science_united_user (email) and science_united_password to ${secret}"
fi
current_rpc=""
if [[ -f "$rpc_file" ]]; then
    current_rpc="$(tr -d '[:space:]' <"$rpc_file")"
fi
if [[ "$current_rpc" != "$rpc_password" ]]; then
    printf '%s\n' "$rpc_password" >"$rpc_file"
    chmod 600 "$rpc_file"
    boinc_changed=1
fi

install_boinc_file "${src}/cc_config.xml" "${BOINC_DIR}/cc_config.xml"
log "link ${BOINC_DIR}/global_prefs_override.xml -> ${prefs_src}"
rm -f "${BOINC_DIR}/global_prefs_override.xml"
ln -sfn "$prefs_src" "${BOINC_DIR}/global_prefs_override.xml"

install_boinc_file "$hosts_list" /etc/boinc-client/hosts.list 0644 1
tmp="$(mktemp)"
grep -vE '^[[:space:]]*(#|$)' "$hosts_list" >"$tmp" || true
if [[ ! -s "$tmp" ]]; then
    warn "files/boinc/hosts.list has no live hosts; remote manager will be denied until you add some"
fi
install_boinc_file "$tmp" "${BOINC_DIR}/remote_hosts.cfg"
rm -f "$tmp"

# Repo copies keep the .sh suffix; PATH names do not.
install_boinc_file "${src}/boinc-config.sh" /usr/local/bin/boinc-config 0755 1
install_boinc_file "${src}/boinc-status.sh" /usr/local/bin/boinc-status 0755 1
install_boinc_file "${src}/boinc-status-all.sh" /usr/local/bin/boinc-status-all 0755 1

systemctl --user daemon-reload
enable_user_service boinc-client.service
if [[ "$boinc_changed" -eq 1 ]] || ! systemctl --user is-active --quiet boinc-client.service; then
    log "restart boinc-client user unit"
    run systemctl --user restart boinc-client.service || run systemctl --user start boinc-client.service
    sleep 3
fi

if command -v firewall-cmd >/dev/null && systemctl is-active --quiet firewalld; then
    if ! sudo firewall-cmd --query-port=31416/tcp >/dev/null 2>&1; then
        log "firewalld allow 31416/tcp"
        sudo firewall-cmd --permanent --add-port=31416/tcp
        sudo firewall-cmd --reload
    fi
fi

log "prefs ${role} from ${prefs_src}"
log "apply role prefs and attach Science United"
BOINC_SECRET="$secret" BOINC_ROLE="$role" BOINC_DIR="$BOINC_DIR" \
    /usr/local/bin/boinc-config || \
    warn "boinc-config failed; retry with /usr/local/bin/boinc-config"
log "status: boinc-status"
log "manager: boincmgr"
