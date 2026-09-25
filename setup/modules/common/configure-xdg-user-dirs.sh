#!/usr/bin/env bash
# Lowercase the eight XDG user dirs and pin them so login does not
# recreate Desktop/Downloads. ~/network is owned by mount-network.sh.

set -euo pipefail
# shellcheck disable=SC1091
. "${REPO_ROOT:-$DOTFILES_ROOT}/setup/lib/lib.sh"

require_user

src_dirs="${SETUP_FILES_DIR}/xdg/user-dirs.dirs"
src_conf="${SETUP_FILES_DIR}/xdg/user-dirs.conf"
dest_dirs="${CONFIG_TARGET_DIR}/user-dirs.dirs"
dest_conf="${CONFIG_TARGET_DIR}/user-dirs.conf"

[[ -f "$src_dirs" ]] || die "missing ${src_dirs}"
[[ -f "$src_conf" ]] || die "missing ${src_conf}"

write_if_changed() {
    local src="$1"
    local dest="$2"

    if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
        return 0
    fi
    log "write ${dest}"
    run install -m 0644 "$src" "$dest"
}

# Move CamelCase XDG dirs to lowercase. Leave a leftover if both exist
# and the old one still has files.
migrate_user_dir() {
    local old="${DOTFILES_HOME}/$1"
    local new="${DOTFILES_HOME}/$2"

    if [[ -e "$old" || -L "$old" ]]; then
        if [[ ! -e "$new" && ! -L "$new" ]]; then
            log "rename ${old} -> ${new}"
            run mv "$old" "$new"
            return 0
        fi
        if [[ -d "$old" && -z "$(find "$old" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
            log "remove empty ${old}"
            run rmdir "$old"
            return 0
        fi
        warn "leave ${old}; ${new} already exists"
        return 0
    fi
    ensure_dir "$new"
}

ensure_dir "$CONFIG_TARGET_DIR"
write_if_changed "$src_dirs" "$dest_dirs"
write_if_changed "$src_conf" "$dest_conf"

migrate_user_dir Desktop desktop
migrate_user_dir Documents documents
migrate_user_dir Downloads downloads
migrate_user_dir Templates templates
migrate_user_dir Public public
migrate_user_dir Music music
migrate_user_dir Pictures pictures
migrate_user_dir Videos videos
