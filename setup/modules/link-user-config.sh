#!/usr/bin/env bash
# Link every directory in the repo config/ folder into ~/.config under the
# same name. Drop a new folder in config/ and the next role run picks it up.
# Loose files in config/ are left alone. Missing or empty config/ is fine.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user
ensure_dir "${CONFIG_TARGET_DIR}"

if [[ ! -d "${CONFIG_SOURCE_DIR}" ]]; then
    warn "skip config links: ${CONFIG_SOURCE_DIR} does not exist yet"
    exit 0
fi

shopt -s nullglob
config_dirs=("${CONFIG_SOURCE_DIR}"/*/)
if [[ "${#config_dirs[@]}" -eq 0 ]]; then
    log "no config directories to link in ${CONFIG_SOURCE_DIR}"
    exit 0
fi

for source_path in "${config_dirs[@]}"; do
    source_path="${source_path%/}"
    dest_name="$(basename "$source_path")"
    dest_path="${CONFIG_TARGET_DIR}/${dest_name}"

    ensure_symlink "$source_path" "$dest_path"
done
