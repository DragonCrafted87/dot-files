#!/usr/bin/env bash
# Shared helpers for setup modules and role scripts.
# Safe to source more than once.

# shellcheck disable=SC2034

if [[ -n "${DOTFILES_LIB_LOADED:-}" ]]; then
    return 0
fi
DOTFILES_LIB_LOADED=1

set -euo pipefail

log() {
    printf '==> %s\n' "$*"
}

warn() {
    printf 'warning: %s\n' "$*" >&2
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

dotfiles_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="${SETUP_DIR:-$dotfiles_here}"

_git_toplevel() {
    git -C "$1" rev-parse --show-toplevel 2>/dev/null || return 1
}

# Never use bare `git rev-parse` — modules are often run from $HOME.
if [[ -z "${REPO_ROOT:-}" ]]; then
    REPO_ROOT="$(_git_toplevel "$SETUP_DIR" || true)"
fi
if [[ -z "${REPO_ROOT:-}" ]]; then
    REPO_ROOT="$(_git_toplevel "$(dirname "$SETUP_DIR")" || true)"
fi
if [[ -z "${REPO_ROOT:-}" && -d "${SETUP_DIR}/../bashrc.d" ]]; then
    REPO_ROOT="$(cd "${SETUP_DIR}/.." && pwd)"
fi

DOTFILES_USER="${DOTFILES_USER:-dragon}"
DOTFILES_HOME="${DOTFILES_HOME:-/home/${DOTFILES_USER}}"
DOTFILES_DIR="${DOTFILES_DIR:-${DOTFILES_HOME}/dot-files}"

if [[ -z "${REPO_ROOT:-}" && -d "${DOTFILES_DIR}/.git" ]]; then
    REPO_ROOT="$(_git_toplevel "$DOTFILES_DIR" || printf '%s' "$DOTFILES_DIR")"
fi
if [[ -z "${REPO_ROOT:-}" ]]; then
    die "cannot find the dot-files repo root from ${SETUP_DIR} (cwd=$(pwd))"
fi

DOTFILES_REPO_URL="${DOTFILES_REPO_URL:-git@github.com:DragonCrafted87/dot-files.git}"
SSH_KEY_PATH="${SSH_KEY_PATH:-${DOTFILES_HOME}/.ssh/id_ed25519}"
DOTFILES_BASHRC="${DOTFILES_BASHRC:-hw_bashrc.sh}"
DOTFILES_TIMEZONE="${DOTFILES_TIMEZONE:-America/Chicago}"
OMP_INSTALL_DIR="${OMP_INSTALL_DIR:-${DOTFILES_HOME}/bin}"
CONFIG_SOURCE_DIR="${CONFIG_SOURCE_DIR:-${REPO_ROOT}/config}"
CONFIG_TARGET_DIR="${CONFIG_TARGET_DIR:-${DOTFILES_HOME}/.config}"
SETUP_FILES_DIR="${SETUP_FILES_DIR:-${SETUP_DIR}/files}"
SETUP_VERSIONS_FILE="${SETUP_VERSIONS_FILE:-${SETUP_DIR}/versions.conf}"
COMPILER_ENV_FILE="${COMPILER_ENV_FILE:-${REPO_ROOT}/bashrc.d/compiler.bashrc}"
# Cross-module flags belong in /tmp, not ~/.config/dot-files.
DOTFILES_QS_RESTART_FLAG="${DOTFILES_QS_RESTART_FLAG:-/tmp/dot-files-$(id -u)-need-qs-restart}"

run() {
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        printf 'dry-run: %s\n' "$*"
        return 0
    fi
    "$@"
}

require_user() {
    if [[ "$(id -un)" != "${DOTFILES_USER}" ]]; then
        die "run this as ${DOTFILES_USER}, not $(id -un)"
    fi
}

# OpenMandriva ships generic x86_64 ISOs even on Zen machines, so rpm
# %{_arch} is not enough. Use the CPU family: AMD family 23+ is Zen and
# takes the znver1 repos.
detect_omv_repo_arch() {
    local vendor family model
    vendor="$(awk -F: '/^vendor_id/{gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo)"
    family="$(awk -F: '/^cpu family/{gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo)"
    model="$(uname -m)"
    if [[ "$model" == "aarch64" ]]; then
        printf '%s\n' aarch64
        return 0
    fi
    if [[ "$vendor" == "AuthenticAMD" && "${family:-0}" -ge 23 ]]; then
        printf '%s\n' znver1
        return 0
    fi
    printf '%s\n' x86_64
}

ensure_dir() {
    local path="$1"
    if [[ -d "$path" ]]; then
        return 0
    fi
    log "create directory ${path}"
    run mkdir -p "$path"
}

ensure_symlink() {
    local target="$1"
    local link="$2"

    if [[ ! -e "$target" && ! -L "$target" ]]; then
        die "symlink target does not exist: ${target}"
    fi

    if [[ -L "$link" ]]; then
        local current
        current="$(readlink "$link")"
        if [[ "$current" == "$target" ]]; then
            return 0
        fi
        log "replace symlink ${link} -> ${target}"
        run ln -sfn "$target" "$link"
        return 0
    fi

    if [[ -e "$link" ]]; then
        local action="${CONFIG_LINK_CLOBBER:-}"
        if [[ -z "$action" && -t 0 ]]; then
            printf '%s exists and is not a symlink.\n' "$link"
            printf '  [m]ove aside  [c]lobber  [s]kip  (default m): '
            read -r action || true
        fi
        case "${action}" in
            c | C | clobber | yes)
                log "clobber ${link}"
                run rm -rf "$link"
                ;;
            s | S | skip)
                warn "skip existing ${link}"
                return 0
                ;;
            *)
                local backup="${link}.bak.$(date +%F-%H%M%S)"
                log "move ${link} -> ${backup}"
                run mv "$link" "$backup"
                ;;
        esac
    fi

    log "link ${link} -> ${target}"
    run ln -sfn "$target" "$link"
}

ensure_repo() {
    local url="$1"
    local dir="$2"

    if [[ -d "${dir}/.git" ]]; then
        log "update ${dir}"
        if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
            printf 'dry-run: git -C %s pull --ff-only\n' "$dir"
            return 0
        fi
        git -C "$dir" pull --ff-only
        return 0
    fi

    if [[ -e "$dir" ]]; then
        die "${dir} exists but is not a git repository"
    fi

    log "clone ${url} -> ${dir}"
    run git clone "$url" "$dir"
}

ensure_file_contents() {
    local path="$1"
    local contents="$2"
    local parent
    parent="$(dirname "$path")"
    ensure_dir "$parent"

    if [[ -f "$path" ]] && [[ "$(cat "$path")" == "$contents" ]]; then
        return 0
    fi

    log "write ${path}"
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        return 0
    fi
    printf '%s\n' "$contents" >"$path"
}

ensure_sudoers_dropin() {
    local name="$1"
    local contents="$2"
    local dest="/etc/sudoers.d/${name}"
    local tmp

    if [[ -f "$dest" ]] && [[ "$(sudo cat "$dest")" == "$contents" ]]; then
        return 0
    fi

    log "write ${dest}"
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        return 0
    fi

    tmp="$(mktemp)"
    printf '%s\n' "$contents" >"$tmp"
    chmod 440 "$tmp"
    visudo -cf "$tmp" >/dev/null
    sudo install -m 0440 "$tmp" "$dest"
    rm -f "$tmp"
}

ensure_packages() {
    if [[ "$#" -eq 0 ]]; then
        return 0
    fi
    log "install packages: $*"
    run sudo dnf install -y "$@"
}

# First exact name that is installed or available. OpenMandriva names are
# lowercase. On 64-bit, libfoo-devel is the 32-bit compat package and
# lib64foo-devel is the real one — try lib64* first even if the caller
# listed the short name first. dnf list can be sloppy about case and
# still exit 0; repoquery + rpm -q stay exact.
pick_pkg() {
    local p avail arch ordered=() rest=()
    arch="$(uname -m)"
    if [[ "$arch" == "x86_64" || "$arch" == "aarch64" ]]; then
        for p in "$@"; do
            if [[ "$p" == lib64* ]]; then
                ordered+=("$p")
            else
                rest+=("$p")
            fi
        done
        set -- "${ordered[@]}" "${rest[@]}"
    fi
    for p in "$@"; do
        if rpm -q "$p" >/dev/null 2>&1; then
            printf '%s\n' "$p"
            return 0
        fi
        avail="$(dnf -q repoquery --available --qf '%{name}\n' "$p" 2>/dev/null | head -n1 || true)"
        if [[ "$avail" == "$p" ]]; then
            printf '%s\n' "$p"
            return 0
        fi
    done
    return 1
}

# Rock 6.0 ships plasma6-* names for KF6 apps. The unprefixed names are
# leftover KF5 packages and file-conflict. Extra args install with the
# plasma6 package (okular extras, etc).
install_kf6_or_plain() {
    local plasma6_name="$1"
    local plain_name="$2"
    shift 2
    local extras=("$@")

    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        log "${plasma6_name} / ${plain_name} package"
        return 0
    fi
    if rpm -q "$plasma6_name" >/dev/null 2>&1; then
        log "${plasma6_name} already installed"
        return 0
    fi
    if rpm -q "$plain_name" >/dev/null 2>&1; then
        log "${plain_name} already installed"
        return 0
    fi
    if dnf list --available "$plasma6_name" >/dev/null 2>&1; then
        ensure_packages "$plasma6_name" "${extras[@]}"
    else
        ensure_packages "$plain_name"
    fi
}

ensure_flatpak_remote() {
    local name="$1"
    local url="$2"
    if flatpak remotes --columns=name 2>/dev/null | grep -qx "$name"; then
        return 0
    fi
    log "flatpak remote ${name}"
    run sudo flatpak remote-add --if-not-exists "$name" "$url"
}

ensure_flatpak() {
    local app="$1"
    if flatpak info "$app" >/dev/null 2>&1; then
        return 0
    fi
    log "flatpak install ${app}"
    run sudo flatpak install -y flathub "$app"
}

remove_packages() {
    local pkg
    local to_remove=()
    for pkg in "$@"; do
        if rpm -q "$pkg" >/dev/null 2>&1; then
            to_remove+=("$pkg")
        fi
    done
    if [[ "${#to_remove[@]}" -eq 0 ]]; then
        return 0
    fi
    log "remove packages: ${to_remove[*]}"
    run sudo dnf remove -y "${to_remove[@]}"
}

enable_service() {
    local unit="$1"
    if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
        return 0
    fi
    log "enable ${unit}"
    run sudo systemctl enable "$unit"
}

enable_user_service() {
    local unit="$1"
    if systemctl --user is-enabled --quiet "$unit" 2>/dev/null; then
        return 0
    fi
    if ! systemctl --user list-unit-files "$unit" >/dev/null 2>&1; then
        warn "user unit ${unit} is not installed yet"
        return 0
    fi
    log "enable --user ${unit}"
    run systemctl --user enable "$unit"
}

disable_service() {
    local unit="$1"
    if ! systemctl list-unit-files "$unit" >/dev/null 2>&1; then
        return 0
    fi
    if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
        log "disable ${unit}"
        run sudo systemctl disable "$unit"
    fi
    if systemctl is-active --quiet "$unit" 2>/dev/null; then
        log "stop ${unit}"
        run sudo systemctl stop "$unit"
    fi
}

ensure_timezone() {
    local tz="$1"
    local current
    current="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
    if [[ "$current" == "$tz" ]]; then
        return 0
    fi
    log "timezone ${tz}"
    run sudo timedatectl set-timezone "$tz"
}

ensure_hostname() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        return 0
    fi
    local current
    current="$(hostnamectl --static 2>/dev/null || hostname)"
    if [[ "$current" == "$name" ]]; then
        return 0
    fi
    log "hostname ${name}"
    run sudo hostnamectl set-hostname "$name"
}

ensure_systemd_dropin() {
    local unit="$1"
    local name="$2"
    local contents="$3"
    local dest="/etc/systemd/system/${unit}.d/${name}.conf"
    local current=""

    if [[ -f "$dest" ]]; then
        current="$(cat "$dest")"
        if [[ "$current" == "$contents" ]]; then
            return 0
        fi
    fi
    log "systemd drop-in ${dest}"
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        return 0
    fi
    sudo mkdir -p "$(dirname "$dest")"
    printf '%s\n' "$contents" | sudo tee "$dest" >/dev/null
    run sudo systemctl daemon-reload
}

# Modules run in a subprocess, so a restart request has to survive on disk.
request_qs_restart() {
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        log "dry-run: would flag qs restart (${DOTFILES_QS_RESTART_FLAG})"
        return 0
    fi
    printf '1\n' >"$DOTFILES_QS_RESTART_FLAG"
}

# Install a .desktop into ~/.local/share/applications and ~/Desktop.
# Marks qs for restart when the start menu needs to reread launchers.
install_user_desktop() {
    local src="$1"
    local name
    local desktop_dir="${XDG_DESKTOP_DIR:-}"
    local apps_dir="${DOTFILES_HOME}/.local/share/applications"
    local changed=0

    name="$(basename "$src")"
    [[ -f "$src" ]] || die "missing ${src}"

    if [[ -z "$desktop_dir" ]] && command -v xdg-user-dir >/dev/null 2>&1; then
        desktop_dir="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
    fi
    desktop_dir="${desktop_dir:-${DOTFILES_HOME}/Desktop}"

    ensure_dir "$desktop_dir"
    ensure_dir "$apps_dir"

    if [[ ! -f "${apps_dir}/${name}" ]] || ! cmp -s "$src" "${apps_dir}/${name}"; then
        log "install desktop ${apps_dir}/${name}"
        run install -m 0755 "$src" "${apps_dir}/${name}"
        changed=1
    fi
    if [[ ! -f "${desktop_dir}/${name}" ]] || ! cmp -s "$src" "${desktop_dir}/${name}"; then
        log "install desktop ${desktop_dir}/${name}"
        run install -m 0755 "$src" "${desktop_dir}/${name}"
        changed=1
    fi

    if [[ "$changed" -eq 1 ]]; then
        if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
            if command -v update-desktop-database >/dev/null 2>&1; then
                update-desktop-database "$apps_dir" >/dev/null 2>&1 || true
            fi
            if command -v xdg-desktop-menu >/dev/null 2>&1; then
                xdg-desktop-menu forceupdate >/dev/null 2>&1 || true
            fi
        fi
        request_qs_restart
    fi
}

restart_qs_if_needed() {
    local starter="${CONFIG_TARGET_DIR}/hypr/scripts/startmenu.sh"

    if [[ ! -f "$DOTFILES_QS_RESTART_FLAG" ]]; then
        return 0
    fi

    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        log "dry-run: would restart qs startmenu"
        return 0
    fi

    rm -f "$DOTFILES_QS_RESTART_FLAG"

    if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && ! pgrep -x Hyprland >/dev/null 2>&1; then
        log "skip qs restart: no Hyprland session"
        return 0
    fi
    if [[ ! -x "$starter" ]]; then
        warn "skip qs restart: missing ${starter}"
        return 0
    fi

    log "restart qs startmenu"
    pkill -f 'qs -c startmenu' >/dev/null 2>&1 || true
    sleep 0.3
    nohup "$starter" >/dev/null 2>&1 &
}

run_module() {
    local module="$1"
    local path="${SETUP_DIR}/modules/${module}.sh"
    [[ -f "$path" ]] || die "missing module: ${path}"
    log "module ${module}"
    # shellcheck disable=SC1090
    bash "$path"
}

record_role() {
    local role="$1"
    OMV_ROLE="$role"
    export OMV_ROLE
    ensure_dir "${CONFIG_TARGET_DIR}/dot-files"
    ensure_file_contents "${CONFIG_TARGET_DIR}/dot-files/role" "$role"
}

valid_role() {
    case "${1:-}" in
        workstation | laptop | htpc | server) return 0 ;;
        *) return 1 ;;
    esac
}

# Print modules for a roles.conf section. @name includes another section.
_role_section() {
    local conf="$1"
    local section="$2"
    local line current=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" ]] && continue
        if [[ "$line" == \[*\] ]]; then
            current="${line#[}"
            current="${current%]}"
            continue
        fi
        [[ "$current" == "$section" ]] || continue
        if [[ "$line" == @* ]]; then
            _role_section "$conf" "${line#@}"
        else
            printf '%s\n' "$line"
        fi
    done <"$conf"
}

# Module lists live in setup/roles.conf so they are easy to find later.
role_modules() {
    local role="$1"
    local conf="${SETUP_DIR}/roles.conf"

    valid_role "$role" || die "unknown role ${role}"
    [[ -f "$conf" ]] || die "missing ${conf}"

    _role_section "$conf" common
    _role_section "$conf" "$role"
}

# KEY=value pins from setup/versions.conf. Skip keys already in the environment.
load_source_versions() {
    local conf="${SETUP_VERSIONS_FILE}"
    local line key value
    [[ -f "$conf" ]] || return 0
    while IFS= read -r line || [[ -n "${line:-}" ]]; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" || "$line" != *=* ]] && continue
        key="${line%%=*}"
        value="${line#*=}"
        [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
        if [[ -z "${!key:-}" ]]; then
            printf -v "$key" '%s' "$value"
            export "$key"
        fi
    done <"$conf"
}

load_compiler_env() {
    local file="${COMPILER_ENV_FILE}"
    [[ -f "$file" ]] || return 0
    # shellcheck disable=SC1090
    . "$file"
}

load_source_versions
load_compiler_env
