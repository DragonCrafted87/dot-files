# Sourced by setup/lib/lib.sh. Not an entry point.

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
