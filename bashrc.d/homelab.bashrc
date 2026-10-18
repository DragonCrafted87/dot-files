#!/usr/bin/env bash
# Advance the homelab checkout and re-run saved roles.
# homelab-upgrade [--dry-run]
# A submodule that is not on main, or whose work tree is dirty, is left
# as it is. The walk uses control/inventory.conf and skips status=out.

homelab-root() {
    if [[ -n "${HOMELAB_ROOT:-}" && -f "${HOMELAB_ROOT}/.gitmodules" ]]; then
        printf '%s\n' "$HOMELAB_ROOT"
        return 0
    fi
    if [[ -f "${HOME}/git-workspace/homelab/.gitmodules" ]]; then
        printf '%s\n' "${HOME}/git-workspace/homelab"
        return 0
    fi
    printf 'homelab-upgrade: cannot find ~/git-workspace/homelab\n' >&2
    return 1
}

homelab-upgrade() {
    local dry=0 root line path branch porcelain setup inventory fabric
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                dry=1
                ;;
            *)
                printf 'usage: homelab-upgrade [--dry-run]\n' >&2
                return 2
                ;;
        esac
        shift
    done

    root="$(homelab-root)" || return 1

    _homelab_pull() {
        local repo="$1"
        local top
        if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            printf 'homelab-upgrade: skip %s (not a checkout)\n' "$repo"
            return 0
        fi
        top="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null || true)"
        if [[ "$(realpath "$top")" != "$(realpath "$repo")" ]]; then
            printf 'homelab-upgrade: skip %s (not a checkout)\n' "$repo"
            return 0
        fi
        if ! git -C "$repo" symbolic-ref -q HEAD >/dev/null 2>&1; then
            printf 'homelab-upgrade: skip %s (detached)\n' "$repo"
            return 0
        fi
        branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD)"
        if [[ "$branch" != main ]]; then
            printf 'homelab-upgrade: skip %s (on %s)\n' "$repo" "$branch"
            return 0
        fi
        porcelain="$(git -C "$repo" status --porcelain)"
        if [[ -n "$porcelain" ]]; then
            printf 'homelab-upgrade: skip %s (dirty)\n' "$repo"
            return 0
        fi
        if [[ "$dry" == 1 ]]; then
            printf 'homelab-upgrade: would git -C %s pull --ff-only\n' "$repo"
            return 0
        fi
        printf 'homelab-upgrade: git -C %s pull --ff-only\n' "$repo"
        git -C "$repo" pull --ff-only
    }

    _homelab_pull "$root" || return 1

    while read -r line; do
        [[ -n "$line" ]] || continue
        path="${line#* }"
        [[ "$path" == /* ]] || path="${root}/${path}"
        _homelab_pull "$path" || return 1
    done < <(git -C "$root" config -f .gitmodules --get-regexp '^submodule\..*\.path$')

    setup=""
    if [[ -f "${HOME}/.config/dot-files/checkouts" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            case "$line" in
                machine-setup=*)
                    setup="${line#machine-setup=}"
                    ;;
            esac
        done <"${HOME}/.config/dot-files/checkouts"
    fi
    if [[ -z "$setup" || ! -d "$setup" ]]; then
        setup="${root}/machine-setup"
    fi
    inventory="${root}/control/inventory.conf"
    fabric="${setup}/setup/control/fabric.py"
    if [[ ! -f "$inventory" ]]; then
        printf 'homelab-upgrade: missing %s\n' "$inventory" >&2
        return 1
    fi
    if [[ ! -f "$fabric" ]]; then
        printf 'homelab-upgrade: missing %s\n' "$fabric" >&2
        return 1
    fi

    if [[ "$dry" == 1 ]]; then
        printf 'homelab-upgrade: would update-role\n'
        printf 'homelab-upgrade: would python3 %s --inventory %s apply\n' "$fabric" "$inventory"
        return 0
    fi

    if ! declare -F update-role >/dev/null 2>&1; then
        local setup_bashrc="${root}/dot-files/bashrc.d/setup.bashrc"
        if [[ -f "$setup_bashrc" ]]; then
            # shellcheck disable=SC1090
            source "$setup_bashrc"
        fi
    fi
    if ! declare -F update-role >/dev/null 2>&1; then
        printf 'homelab-upgrade: update-role is not defined\n' >&2
        return 1
    fi
    update-role || return 1
    python3 "$fabric" --inventory "$inventory" apply
}
