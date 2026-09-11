#!/usr/bin/env bash
# Copy live Flatpak OBS config into the repo. Drops logs, crash dumps,
# plugin caches, and service.json (stream keys).
#
#   ./setup/utility/harvest-obs.sh

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "${here}/../.." && pwd)"
src="${HOME}/.var/app/com.obsproject.Studio/config/obs-studio"
dest="${repo}/setup/files/obs"

if [[ ! -d "$src" ]]; then
    printf 'error: %s is missing; is the OBS Flatpak configured?\n' "$src" >&2
    exit 1
fi

mkdir -p "$dest"
rsync -a --delete \
    --exclude 'logs/' \
    --exclude 'crashes/' \
    --exclude 'profiler_data/' \
    --exclude 'plugin_config/' \
    --exclude 'service.json' \
    "$src/" "$dest/"

printf '==> wrote %s\n' "$dest"
printf '    service.json was skipped (stream keys). Re-enter the stream\n'
printf '    key on a new box. Review scenes for local file paths, then\n'
printf '    commit setup/files/obs.\n'
