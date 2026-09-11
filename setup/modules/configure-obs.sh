#!/usr/bin/env bash
# Replay harvested Flatpak OBS config onto the workstation.
# Stream keys are not stored in the repo (service.json is skipped).

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

src="${SETUP_FILES_DIR}/obs"
dest="${DOTFILES_HOME}/.var/app/com.obsproject.Studio/config/obs-studio"
nebula="${dest}/basic/scenes/nebula_background.jpg"

if [[ ! -d "$src" ]] || [[ -z "$(find "$src" -type f ! -name '.gitkeep' -print -quit 2>/dev/null)" ]]; then
    warn "no harvested OBS config in ${src}; run setup/utility/harvest-obs.sh"
    exit 0
fi

ensure_dir "$dest"
log "sync OBS config from ${src}"
if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
    exit 0
fi

rsync -a --delete \
    --exclude 'logs/' \
    --exclude 'crashes/' \
    --exclude 'profiler_data/' \
    --exclude 'plugin_config/' \
    --exclude 'service.json' \
    --exclude '.gitkeep' \
    "${src}/" "${dest}/"

# Scene collections store absolute paths. Point the Image source at the
# copy that ships next to Untitled.json, not the old loose file in $HOME.
if [[ -f "$nebula" ]]; then
    shopt -s nullglob
    for scene in "${dest}/basic/scenes/"*.json "${dest}/basic/scenes/"*.json.bak; do
        [[ -f "$scene" ]] || continue
        sed -i \
            -e 's|/home/dragon/360_F_1423685604_x8B0ES8ArnfKfnAZsg5duuWNAHxR6oeD.jpg|'