#!/usr/bin/env bash
# Remove user-installed rpms and extra Flatpaks that are not part of this
# role. Home files and the role's declared packages stay.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

role="${OMV_ROLE:-}"
[[ -n "$role" ]] || die "OMV_ROLE is unset; run: ./setup/role.sh <role> reset"
valid_role "$role" || die "unknown role ${role}"

collect_role_packages() {
    local module path
    declare -gA KEEP_PACKAGES=()
    declare -gA KEEP_FLATPAKS=()

    while IFS= read -r module; do
        path="${SETUP_DIR}/modules/${module}.sh"
        [[ -f "$path" ]] || continue
        # Names that follow ensure_packages on the same or later lines
        # until a line that is not a package token.
        awk '
            function add(p) {
                gsub(/^[ \t]+|[ \t\\]+$/, "", p)
                if (p != "" && p !~ /^#/ && p !~ /\$/ && p ~ /^[A-Za-z0-9._+-]+$/)
                    print p
            }
            $1 == "ensure_packages" {
                for (i = 2; i <= NF; i++) add($i)
                if ($0 ~ /\\$/) more = 1
                next
            }
            more {
                for (i = 1; i <= NF; i++) add($i)
                if ($0 !~ /\\$/) more = 0
            }
        ' "$path"
    done < <(role_modules "$role")
}

collect_role_flatpaks() {
    local module path
    while IFS= read -r module; do
        path="${SETUP_DIR}/modules/${module}.sh"
        [[ -f "$path" ]] || continue
        awk '
            $1 == "ensure_flatpak" { print $2 }
        ' "$path"
    done < <(role_modules "$role")
}

mapfile -t declared < <(collect_role_packages | sort -u)
keep_file="${SETUP_FILES_DIR}/packages/never-remove.list"
mapfile -t never < <(grep -vE '^[[:space:]]*(#|$)' "$keep_file" 2>/dev/null || true)

declare -A keep=()
for pkg in "${declared[@]}" "${never[@]}"; do
    [[ -n "$pkg" ]] && keep["$pkg"]=1
done

log "role ${role} declared ${#declared[@]} packages plus ${#never[@]} never-remove names"

mapfile -t user_installed < <(dnf repoquery --userinstalled --qf '%{name}' 2>/dev/null | sort -u || true)
if [[ "${#user_installed[@]}" -eq 0 ]]; then
    warn "dnf repoquery --userinstalled returned nothing; skip rpm prune"
    user_installed=()
fi

to_remove=()
for pkg in "${user_installed[@]}"; do
    [[ -z "$pkg" ]] && continue
    if [[ -n "${keep[$pkg]:-}" ]]; then
        continue
    fi
    # Keep kernels and task metapackages that match never-remove prefixes.
    case "$pkg" in
        kernel*|grub2*|systemd*|glibc*|dnf*|rpm-*|lib64*|python-*|perl-*|kf6-*|qt6-*)
            continue
            ;;
    esac
    to_remove+=("$pkg")
done

if [[ "${#to_remove[@]}" -gt 0 ]]; then
    log "user-installed extras (${#to_remove[@]}):"
    printf '    %s\n' "${to_remove[@]}"
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        printf 'dry-run: sudo dnf remove -y %s\n' "${to_remove[*]}"
    elif [[ "${RESET_CONFIRM:-}" == "yes" ]]; then
        run sudo dnf remove -y "${to_remove[@]}"
    else
        warn "not removing rpms; re-run with RESET_CONFIRM=yes"
    fi
else
    log "no extra user-installed rpms"
fi

mapfile -t wanted_flatpaks < <(collect_role_flatpaks | sort -u)
declare -A want_fp=()
for app in "${wanted_flatpaks[@]}"; do
    [[ -n "$app" ]] && want_fp["$app"]=1
done

if command -v flatpak >/dev/null 2>&1; then
    mapfile -t installed_fps < <(flatpak list --app --columns=application 2>/dev/null | sort -u || true)
    fp_remove=()
    for app in "${installed_fps[@]}"; do
        [[ -z "$app" || "$app" == "Application" ]] && continue
        if [[ -z "${want_fp[$app]:-}" ]]; then
            fp_remove+=("$app")
        fi
    done
    if [[ "${#fp_remove[@]}" -gt 0 ]]; then
        log "extra flatpaks (${#fp_remove[@]}):"
        printf '    %s\n' "${fp_remove[@]}"
        if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
            printf 'dry-run: flatpak uninstall -y %s\n' "${fp_remove[*]}"
        elif [[ "${RESET_CONFIRM:-}" == "yes" ]]; then
            run sudo flatpak uninstall -y "${fp_remove[@]}"
        else
            warn "not removing flatpaks; re-run with RESET_CONFIRM=yes"
        fi
    else
        log "no extra flatpaks"
    fi
fi
