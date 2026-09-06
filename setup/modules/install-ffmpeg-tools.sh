#!/usr/bin/env bash
# Binaries used by scripts/ffmpeg.py and bashrc.d/ffmpeg.bashrc.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

ensure_packages ffmpeg dvdauthor genisoimage

if ! command -v mkisofs >/dev/null 2>&1 && command -v genisoimage >/dev/null 2>&1; then
    dest="/usr/local/bin/mkisofs"
    if [[ ! -e "$dest" ]]; then
        log "link ${dest} -> genisoimage"
        run sudo ln -sfn "$(command -v genisoimage)" "$dest"
    fi
fi

if ! command -v ffprobe >/dev/null 2>&1; then
    warn "ffprobe not on PATH after ffmpeg install"
fi
