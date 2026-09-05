#!/usr/bin/env bash
# Role shorthand. The saved role lives in ~/.config/dot-files/role.

update-role() {
    local role_file="${HOME}/.config/dot-files/role"
    local setup="${PATH_BASH_SETTINGS:-$HOME/dot-files}/setup/role.sh"
    local role=""

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
    if [[ ! -x "$setup" && ! -f "$setup" ]]; then
        printf 'missing %s\n' "$setup" >&2
        return 1
    fi
    printf 'update-role: %s\n' "$role"
    bash "$setup" "$role" "$@"
}
