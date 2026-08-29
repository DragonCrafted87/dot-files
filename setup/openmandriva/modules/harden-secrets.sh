#!/usr/bin/env bash
# Tighten permissions on secret files if they exist. Missing files are
# skipped so this can run before transfer-secrets.sh.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

ensure_mode() {
    local path="$1"
    local mode="$2"
    if [[ ! -e "$path" ]]; then
        return 0
    fi
    local current
    current="$(stat -c '%a' "$path" 2>/dev/null || true)"
    if [[ "$current" == "$mode" ]]; then
        return 0
    fi
    log "chmod ${mode} ${path}"
    run chmod "$mode" "$path"
}

if [[ -d "${DOTFILES_HOME}/.ssh" ]]; then
    ensure_mode "${DOTFILES_HOME}/.ssh" 700
fi

list="${SETUP_FILES_DIR}/secrets.list"
if [[ -f "$list" ]]; then
    while IFS= read -r rel || [[ -n "${rel:-}" ]]; do
        [[ -z "$rel" || "$rel" == \#* ]] && continue
        ensure_mode "${DOTFILES_HOME}/${rel}" 600
    done <"$list"
fi

shopt -s nullglob
for key in "${DOTFILES_HOME}/.ssh"/id_*; do
    [[ "$key" == *.pub ]] && continue
    ensure_mode "$key" 600
done
for pub in "${DOTFILES_HOME}/.ssh"/id_*.pub; do
    ensure_mode "$pub" 644
done
if [[ -f "${DOTFILES_HOME}/.ssh/config" || -L "${DOTFILES_HOME}/.ssh/config" ]]; then
    ensure_mode "${DOTFILES_HOME}/.ssh/config" 600
fi
