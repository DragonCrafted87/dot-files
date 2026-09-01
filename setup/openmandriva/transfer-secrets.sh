#!/usr/bin/env bash
# Copy sensitive files from this machine onto a new box over SSH.
# Run from the working computer after the new host has a user and sshd.
#
#   ./setup/openmandriva/transfer-secrets.sh dragon@newbox.lan
#
# Edit files/secrets.list to add more paths.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
list="${here}/files/secrets.list"
target="${1:-}"

if [[ -z "$target" ]]; then
    printf 'usage: %s user@host\n' "$0" >&2
    exit 1
fi

if [[ ! -f "$list" ]]; then
    printf 'error: missing %s\n' "$list" >&2
    exit 1
fi

ssh_cmd() {
    # shellcheck disable=SC2086
    ssh ${DOTFILES_SSH_OPTS:-} -o ForwardX11=no "$@"
}

scp_cmd() {
    # shellcheck disable=SC2086
    scp ${DOTFILES_SSH_OPTS:-} -o ForwardX11=no "$@"
}

copied=0
skipped=0
while IFS= read -r rel || [[ -n "$rel" ]]; do
    [[ -z "$rel" || "$rel" == \#* ]] && continue
    src="${HOME}/${rel}"
    if [[ ! -e "$src" ]]; then
        printf 'skip (missing): %s\n' "$src"
        skipped=$((skipped + 1))
        continue
    fi
    remote_dir="$(dirname "$rel")"
    if [[ "$remote_dir" != "." ]]; then
        ssh_cmd "$target" "mkdir -p -- ${remote_dir}"
    fi
    printf 'copy %s -> %s:%s\n' "$src" "$target" "$rel"
    scp_cmd -p "$src" "${target}:${rel}"
    copied=$((copied + 1))
done <"$list"

printf '==> copied %s, skipped %s\n' "$copied" "$skipped"
printf '    on the new box, re-run the role script or:\n'
printf '      %s/modules/harden-secrets.sh\n' "$here"
