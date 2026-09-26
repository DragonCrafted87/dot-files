# shellcheck shell=bash
# Sourced by setup/lib/lib.sh. Not an entry point.

# Resolve setup/modules/<name>.sh or setup/modules/<area>/<name>.sh.
# roles.conf stores the basename. A name with a slash is taken as a path
# under setup/modules/.
find_module() {
    local module="${1:-}"
    local base="${SETUP_DIR}/modules"
    local path candidate
    local matches=()

    [[ -n "$module" ]] || return 1
    module="${module%.sh}"

    if [[ "$module" == */* ]]; then
        path="${base}/${module}.sh"
        if [[ -f "$path" ]]; then
            printf '%s\n' "$path"
            return 0
        fi
        return 1
    fi

    path="${base}/${module}.sh"
    if [[ -f "$path" ]]; then
        printf '%s\n' "$path"
        return 0
    fi

    for candidate in "${base}"/*/"${module}.sh"; do
        [[ -f "$candidate" ]] || continue
        matches+=("$candidate")
    done

    if [[ "${#matches[@]}" -eq 1 ]]; then
        printf '%s\n' "${matches[0]}"
        return 0
    fi
    if [[ "${#matches[@]}" -gt 1 ]]; then
        die "ambiguous module ${module}: ${matches[*]}"
    fi
    return 1
}

run_module() {
    local module="$1"
    local path
    path="$(find_module "$module")" || die "missing module: ${module}"
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

# Role currently being applied, else the saved file.
saved_role() {
    local path="${CONFIG_TARGET_DIR}/dot-files/role"
    local role="${OMV_ROLE:-}"
    if [[ -z "$role" && -f "$path" ]]; then
        role="$(<"$path")"
        role="${role%%$'\n'*}"
    fi
    printf '%s\n' "$role"
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
