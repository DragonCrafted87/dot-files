#!/usr/bin/env bash
# Link only the safe VS Code User files. ~/.config/Code must stay a real
# directory so Chromium profile state (Local State, Cache) is not replaced
# by the git tree. That replacement is what made VS Code write {} over
# settings.json.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

src="${CONFIG_SOURCE_DIR}/Code/User"
code_dest="${CONFIG_TARGET_DIR}/Code"
dest="${code_dest}/User"

if [[ ! -d "$src" ]]; then
    warn "no ${src}; run setup/utility/harvest-vscode.sh"
    exit 0
fi

# Previous role runs linked the whole config/Code tree. Undo that.
if [[ -L "$code_dest" ]]; then
    log "replace symlink ${code_dest} with a real VS Code profile directory"
    if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
        rm -f "$code_dest"
    fi
fi
ensure_dir "$dest"

shopt -s nullglob
for file in "$src"/*; do
    [[ -f "$file" ]] || continue
    name="$(basename "$file")"
    case "$name" in
        settings.json | keybindings.json | locale.json) ;;
        *)
            continue
            ;;
    esac
    ensure_symlink "$file" "${dest}/${name}"
done

if [[ -d "${src}/snippets" ]]; then
    ensure_symlink "${src}/snippets" "${dest}/snippets"
fi
