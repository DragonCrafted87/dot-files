#!/usr/bin/env bash
# Temporary forwarder. Checks out machine-setup for this role, records
# both paths, and execs that checkout's role.sh. Remove this script
# once every machine has both checkouts.

set -euo pipefail

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

helper_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dotfiles_repo="$(cd "${helper_dir}/.." && pwd)"
role_file="${HOME}/.config/dot-files/role"
checkouts_file="${HOME}/.config/dot-files/checkouts"
homelab_url="${HOMELAB_REPO_URL:-git@github.com:DragonCrafted87/homelab.git}"
setup_url="${MACHINE_SETUP_REPO_URL:-git@github.com:DragonCrafted87/os-configurations.git}"
homelab_dir="${HOMELAB_DIR:-${HOME}/git-workspace/homelab}"
standalone_dir="${STANDALONE_SETUP:-${HOME}/machine-setup}"

role_from_args() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            workstation | htpc | server)
                printf '%s\n' "$arg"
                return 0
                ;;
        esac
    done
    return 1
}

saved_role() {
    [[ -f "$role_file" ]] || return 1
    tr -d '[:space:]' <"$role_file"
}

have_role_sh() {
    [[ -f "$1/setup/role.sh" ]]
}

read_machine_setup() {
    local line
    [[ -f "$checkouts_file" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            machine-setup=*)
                printf '%s\n' "${line#machine-setup=}"
                return 0
                ;;
        esac
    done <"$checkouts_file"
    return 1
}

write_checkouts() {
    local dots="$1" setup_root="$2"
    dots="$(realpath "$dots")"
    setup_root="$(realpath "$setup_root")"
    mkdir -p -- "$(dirname "$checkouts_file")"
    printf 'dot-files=%s\nmachine-setup=%s\n' "$dots" "$setup_root" >"$checkouts_file"
}

exec_role() {
    local setup_root="$1"
    shift
    have_role_sh "$setup_root" || die "missing ${setup_root}/setup/role.sh"
    write_checkouts "$dotfiles_repo" "$setup_root"
    exec bash "${setup_root}/setup/role.sh" "$@"
}

recorded="$(read_machine_setup || true)"
if [[ -n "$recorded" ]] && have_role_sh "$recorded"; then
    exec_role "$recorded" "$@"
fi

role="$(role_from_args "$@")" || role="$(saved_role)" \
    || die "no role saved; pass workstation, htpc, or server once"

case "$role" in
    workstation)
        if git -C "$homelab_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            if ! have_role_sh "${homelab_dir}/machine-setup"; then
                git -C "$homelab_dir" submodule update --init machine-setup
            fi
        elif [[ -e "$homelab_dir" ]]; then
            die "${homelab_dir} exists and is not a git checkout"
        else
            mkdir -p -- "$(dirname "$homelab_dir")"
            git clone "$homelab_url" "$homelab_dir"
            git -C "$homelab_dir" submodule update --init
        fi
        exec_role "${homelab_dir}/machine-setup" "$@"
        ;;
    htpc | server)
        if have_role_sh "$standalone_dir"; then
            :
        elif [[ -e "$standalone_dir" ]]; then
            die "${standalone_dir} exists and has no setup/role.sh"
        else
            git clone "$setup_url" "$standalone_dir"
        fi
        exec_role "$standalone_dir" "$@"
        ;;
    *)
        die "no role saved; pass workstation, htpc, or server once"
        ;;
esac
