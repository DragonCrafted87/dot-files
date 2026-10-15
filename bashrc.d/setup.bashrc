#!/usr/bin/env bash
# Role shorthand and repo helpers.
# Saved role: ~/.config/dot-files/role
# Saved subroles: ~/.config/dot-files/subroles
# update-role reads machine-setup from ~/.config/dot-files/checkouts.
# update-dot-files finds this repo from $DOTFILES_ROOT, else
# ~/.config/dot-files/root, else ~/dot-files.

dotfiles-root() {
    local recorded="${HOME}/.config/dot-files/root"
    if [[ -n "${DOTFILES_ROOT:-}" && -d "$DOTFILES_ROOT" ]]; then
        printf '%s\n' "$DOTFILES_ROOT"
        return 0
    fi
    if [[ -n "${PATH_BASH_SETTINGS:-}" && -d "$PATH_BASH_SETTINGS" ]]; then
        printf '%s\n' "$PATH_BASH_SETTINGS"
        return 0
    fi
    if [[ -f "$recorded" ]]; then
        local path
        path="$(tr -d '[:space:]' <"$recorded")"
        if [[ -n "$path" && -d "$path" ]]; then
            printf '%s\n' "$path"
            return 0
        fi
    fi
    if [[ -d "${HOME}/dot-files" ]]; then
        printf '%s\n' "${HOME}/dot-files"
        return 0
    fi
    return 1
}

update-dot-files() {
    local repo cwd
    repo="$(dotfiles-root)" || {
        printf 'cannot find the dot-files repo\n' >&2
        printf 'source bashrc from inside the clone once, or clone to ~/dot-files\n' >&2
        return 1
    }
    cwd="$PWD"
    if ! cd "$repo"; then
        printf 'cannot cd to %s\n' "$repo" >&2
        return 1
    fi
    printf 'update-dot-files: %s\n' "$repo"
    git pull
    local rc=$?
    # shellcheck disable=SC1090
    source ~/.bashrc
    cd "$cwd" || true
    return "$rc"
}

machine-setup-root() {
    local file="${HOME}/.config/dot-files/checkouts"
    local line value
    if [[ ! -f "$file" ]]; then
        printf 'missing %s\n' "$file" >&2
        return 1
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            '' | \#*)
                continue
                ;;
            machine-setup=*)
                value="${line#machine-setup=}"
                value="${value#"${value%%[![:space:]]*}"}"
                value="${value%"${value##*[![:space:]]}"}"
                if [[ -z "$value" || ! -d "$value" ]]; then
                    printf 'machine-setup in %s is not a directory: %s\n' "$file" "$value" >&2
                    return 1
                fi
                printf '%s\n' "$value"
                return 0
                ;;
        esac
    done <"$file"
    printf 'missing machine-setup in %s\n' "$file" >&2
    return 1
}

# Fast-forward a branch whose git status is empty. A dirty tree or a
# detached HEAD stays as it is. dry=1 prints the pull and does not run it.
pull-clean-machine-setup() {
    local root="$1"
    local dry="$2"
    local status_text
    if ! git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        printf 'update-role: %s is not a git work tree\n' "$root" >&2
        return 1
    fi
    if ! git -C "$root" symbolic-ref -q HEAD >/dev/null 2>&1; then
        printf 'update-role: detached HEAD %s; leaving it\n' "$root"
        return 0
    fi
    if ! status_text="$(git -C "$root" status --porcelain)"; then
        printf 'update-role: cannot read %s\n' "$root" >&2
        return 1
    fi
    if [[ -n "$status_text" ]]; then
        printf 'update-role: dirty %s; leaving it\n' "$root"
        return 0
    fi
    if [[ "$dry" == "1" ]]; then
        printf 'update-role: would git pull --ff-only %s\n' "$root"
        return 0
    fi
    printf 'update-role: git pull --ff-only %s\n' "$root"
    git -C "$root" pull --ff-only
}

update-role() {
    local role_file="${HOME}/.config/dot-files/role"
    local setup_root setup role arg dry=0
    setup_root="$(machine-setup-root)" || return 1
    setup="${setup_root}/setup/role.sh"
    if [[ ! -f "$setup" ]]; then
        printf 'missing %s\n' "$setup" >&2
        return 1
    fi

    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "--list-subroles" ]]; then
        bash "$setup" "$@"
        return $?
    fi

    if [[ "${1:-}" == workstation || "${1:-}" == htpc || "${1:-}" == server ]]; then
        role="$1"
        shift
    elif [[ -f "$role_file" ]]; then
        role="$(tr -d '[:space:]' <"$role_file")"
    fi

    if [[ -z "${role:-}" ]]; then
        printf 'no role saved at %s\n' "$role_file" >&2
        printf 'pass workstation, htpc, or server once\n' >&2
        return 1
    fi

    for arg in "$@"; do
        case "$arg" in
            -h | --help | --list-subroles | --dry-run)
                dry=1
                ;;
        esac
    done

    printf 'update-role: %s (%s)\n' "$role" "$setup_root"
    if ! pull-clean-machine-setup "$setup_root" "$dry"; then
        return 1
    fi
    bash "$setup" "$role" "$@"
    return $?
}

enable-subrole() {
    if [[ -z "${1:-}" ]]; then
        printf 'usage: enable-subrole NAME\n' >&2
        return 1
    fi
    update-role --enable-subrole "$1"
}

disable-subrole() {
    if [[ -z "${1:-}" ]]; then
        printf 'usage: disable-subrole NAME\n' >&2
        return 1
    fi
    update-role --disable-subrole "$1"
}

list-subroles() {
    local setup_root setup
    setup_root="$(machine-setup-root)" || return 1
    setup="${setup_root}/setup/role.sh"
    if [[ ! -f "$setup" ]]; then
        printf 'missing %s\n' "$setup" >&2
        return 1
    fi
    bash "$setup" --list-subroles
}
