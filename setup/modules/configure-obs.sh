#!/usr/bin/env bash
# Replay harvested Flatpak OBS config onto the workstation.
# Stream keys are not stored in the repo (service.json is skipped).

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

src="${SETUP_FILES_DIR}/obs"
dest="${DOTFILES_HOME}/.var/app/com.obsproject.Studio/config/obs-studio"

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
