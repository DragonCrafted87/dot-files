#!/usr/bin/env bash
# Dynamic host subroles. Sourced by setup/lib/lib.sh.
# Saved list: ~/.config/dot-files/subroles
# roles.conf sections: [subrole.<name>]
# Not derived from the hostname.

subroles_file() {
    printf '%s\n' "${CONFIG_TARGET_DIR}/dot-files/subroles"
}

known_subroles() {
    local conf="${SETUP_DIR}/roles.conf"
    local line current=""
    [[ -f "$conf" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ "$line" == \[*\] ]] || continue
        current="${line#[}"
        current="${current%]}"
        if [[ "$current" == subrole.* ]]; then
            printf '%s\n' "${current#subrole.}"
        fi
    done <"$conf"
}

valid_subrole() {
    local want="${1:-}" name
    [[ -n "$want" ]] || return 1
    while IFS= read -r name; do
        [[ "$name" == "$want" ]] && return 0
    done < <(known_subroles)
    return 1
}

read_saved_subroles() {
    local file name
    file="$(subroles_file)"
    [[ -f "$file" ]] || return 0
    while IFS= read -r name || [[ -n "$name" ]]; do
        name="${name%%#*}"
        name="${name#"${name%%[![:space:]]*}"}"
        name="${name%"${name##*[![:space:]]}"}"
        [[ -n "$name" ]] && printf '%s\n' "$name"
    done <"$file"
}

has_subrole() {
    local want="${1:-}" name
    [[ -n "$want" ]] || return 1
    while IFS= read -r name; do
        [[ "$name" == "$want" ]] && return 0
    done < <(read_saved_subroles)
    return 1
}

load_subroles_env() {
    local names=() item
    while IFS= read -r item; do
        names+=("$item")
    done < <(read_saved_subroles)
    if [[ "${#names[@]}" -gt 0 ]]; then
        OMV_SUBROLES="${names[*]}"
    else
        OMV_SUBROLES=""
    fi
    export OMV_SUBROLES
}

record_subroles() {
    local file dest name
    file="$(subroles_file)"
    dest="$(mktemp)"
    for name in "$@"; do
        [[ -n "$name" ]] || continue
        printf '%s\n' "$name"
    done | awk 'NF && !seen[$0]++' | sort >"$dest"
    ensure_dir "$(dirname "$file")"
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        log "dry-run: write ${file}"
        rm -f "$dest"
        load_subroles_env
        return 0
    fi
    if [[ -f "$file" ]] && cmp -s "$dest" "$file"; then
        rm -f "$dest"
        load_subroles_env
        return 0
    fi
    log "write ${file}"
    mv "$dest" "$file"
    load_subroles_env
}

enable_saved_subrole() {
    local name="$1" existing=() item
    valid_subrole "$name" || die "unknown subrole ${name}"
    while IFS= read -r item; do
        existing+=("$item")
    done < <(read_saved_subroles)
    existing+=("$name")
    record_subroles "${existing[@]}"
}

disable_saved_subrole() {
    local name="$1" keep=() item
    while IFS= read -r item; do
        [[ "$item" == "$name" ]] && continue
        keep+=("$item")
    done < <(read_saved_subroles)
    record_subroles "${keep[@]}"
}

read_saved_role() {
    local file="${CONFIG_TARGET_DIR}/dot-files/role"
    [[ -f "$file" ]] || return 1
    tr -d '[:space:]' <"$file"
}

valid_role() {
    case "${1:-}" in
        workstation | htpc | server) return 0 ;;
        *) return 1 ;;
    esac
}

record_role() {
    local role="$1"
    OMV_ROLE="$role"
    export OMV_ROLE
    ensure_dir "${CONFIG_TARGET_DIR}/dot-files"
    ensure_file_contents "${CONFIG_TARGET_DIR}/dot-files/role" "$role"
    load_subroles_env
}

role_modules() {
    local role="$1"
    local conf="${SETUP_DIR}/roles.conf"
    local sub

    valid_role "$role" || die "unknown role ${role}"
    [[ -f "$conf" ]] || die "missing ${conf}"

    _role_section "$conf" common
    _role_section "$conf" "$role"
    while IFS= read -r sub; do
        [[ -n "$sub" ]] || continue
        _role_section "$conf" "subrole.${sub}"
    done < <(read_saved_subroles)
}

subrole_modules() {
    local name="$1"
    local conf="${SETUP_DIR}/roles.conf"
    valid_subrole "$name" || die "unknown subrole ${name}"
    [[ -f "$conf" ]] || die "missing ${conf}"
    _role_section "$conf" "subrole.${name}"
}
