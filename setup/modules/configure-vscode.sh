#!/usr/bin/env bash
# Link only the safe VS Code User files. Do not link ~/.config/Code itself;
# globalStorage and workspaceStorage hold tokens and machine state.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

src="${CONFIG_SOURCE_DIR}/Code/User"
dest="${CONFIG_TARGET_DIR}/Code/User"
ensure_dir "$dest"

if [[ ! -d "$src" ]]; then
    warn "no ${src}; run setup/utility/harvest-vscode.sh"
    exit 0
fi

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
