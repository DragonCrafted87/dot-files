#!/usr/bin/env bash
# Copy live VS Code User settings into the repo. Skips storage, state,
# and anything that looks like a token.
#
#   ./setup/utility/harvest-vscode.sh

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "${here}/../.." && pwd)"
src="${HOME}/.config/Code/User"
dest="${repo}/config/Code/User"

if [[ ! -d "$src" ]]; then
    printf 'error: %s is missing\n' "$src" >&2
    exit 1
fi

mkdir -p "$dest"
for name in settings.json keybindings.json locale.json; do
    if [[ -f "${src}/${name}" ]]; then
        cp -a "${src}/${name}" "${dest}/${name}"
        printf '==> %s\n' "${dest}/${name}"
    fi
done
if [[ -d "${src}/snippets" ]]; then
    mkdir -p "${dest}/snippets"
    cp -a "${src}/snippets/." "${dest}/snippets/"
    printf '==> %s\n' "${dest}/snippets"
fi

printf 'review the files, then commit config/Code\n'
