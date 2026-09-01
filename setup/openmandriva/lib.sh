#!/usr/bin/env bash
# Shared helpers for setup/openmandriva modules and role scripts.
# Safe to source more than once.

# shellcheck disable=SC2034

if [[ -n "${DOTFILES_LIB_LOADED:-}" ]]; then
    return 0
fi
DOTFILES_LIB_LOADED=1

set -euo pipefail

dotfiles_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENMANDRIVA_SETUP_DIR="${OPENMANDRIVA_SETUP_DIR:-$dotfiles_here}"
REPO_ROOT="$(cd "${OPENMANDRIVA_SETUP_DIR}/../.." && pwd)"

DOTFILES_USER="${DOTFILES_USER:-dragon}"
DOTFILES_HOME="${DOTFILES_HOME:-/home/${DOTFILES_USER}}"
DOTFILES_DIR="${DOTFILES_DIR:-${DOTFILES_HOME}/dot-files}"
DOTFILES_REPO_URL="${DOTFILES_REPO_URL:-git@github.com:DragonCrafted87/dot-files.git}"
SSH_KEY_PATH="${SSH_KEY_PATH:-${DOTFILES_HOME}/.ssh/id_ed25519}"
DOTFILES_BASHRC="${DOTFILES_BASHRC:-hw_bashrc.sh}"
DOTFILES_TIMEZONE="${DOTFILES_TIMEZONE:-America/Chicago}"
OMP_INSTALL_DIR="${OMP_INSTALL_DIR:-${DOTFILES_HOME}/bin}"
CONFIG_SOURCE_DIR="${CONFIG_SOURCE_DIR:-${REPO_ROOT}/config}"
CONFIG_TARGET_DIR="${CONFIG_TARGET_DIR:-${DOTFILES_HOME}/.config}"
SETUP_FILES_DIR="${SETUP_FILES_DIR:-${OPENMANDRIVA_SETUP_DIR}/files}"

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

run_module() {
    local module="$1"
    local path="${OPENMANDRIVA_SETUP_DIR}/modules/${module}.sh"
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
