#!/usr/bin/env bash
# Role shorthand. Saved role: ~/.config/dot-files/role
# Repo location: $DOTFILES_ROOT, else ~/.config/dot-files/root, else ~/dot-files

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

update-role() {
    local role_file="${HOME}/.config/dot-files/role"
    local repo role setup cwd
    repo="$(dotfiles-root)" || {
        printf 'cannot find the dot-files repo\n' >&2
        printf 'source bashrc from inside the clone once, or clone to ~/dot-files\n' >&2
        return 1
    }
    setup="${repo}/setup/role.sh"

    if [[ "${1:-}" == workstation || "${1:-}" == laptop || "${1:-}" == htpc || "${1:-}" == server ]]; then
        role="$1"
        shift
    elif [[ -f "$role_file" ]]; then
        role="$(tr -d '[:space:]' <"$role_file")"
    fi

    if [[ -z "$role" ]]; then
        printf 'no role saved at %s\n' "$role_file" >&2
        printf 'pass workstation, laptop, htpc, or server once\n' >&2
        return 1
    fi
    if [[ ! -f "$setup" ]]; then
        printf 'missing %s\n' "$setup" >&2
        return 1
    fi

    cwd="$PWD"
    if ! cd "$repo"; then
        printf 'cannot cd to %s\n' "$repo" >&2
        return 1
    fi
    printf 'update-role: %s (%s)\n' "$role" "$repo"
    bash ./setup/role.sh "$role" "$@"
    local rc=$?
    cd "$cwd" || true
    return "$rc"
}
