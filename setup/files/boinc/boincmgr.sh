#!/usr/bin/env bash
# Launch the manager against the native data dir.
# Installed on PATH as ~/bin/boincmgr (ahead of /usr/local/bin).
set -euo pipefail
exec /usr/local/bin/boincmgr --datadir "${HOME}/.local/share/boinc" "$@"
