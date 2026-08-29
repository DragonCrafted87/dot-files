#!/usr/bin/env bash
# Run from a working computer against a fresh OpenMandriva box that
# already has a user and sshd. Copies secrets, copies first-boot.sh,
# then runs first-boot over SSH so gh device login can be finished here.
#
#   ./setup/openmandriva/init-remote.sh dragon@newbox.lan workstation

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="${1:-}"
role="${2:-}"

if [[ -z "$target" || -z "$role" ]]; then
    printf 'usage: %s user@host workstation|laptop|htpc|server\n' "$0" >&2
    exit 1
fi

case "$role" in
    workstation | laptop | htpc | server) ;;
    *)
        printf 'error: unknown role %s\n' "$role" >&2
        exit 1
        ;;
esac

printf '==> copy secrets to %s\n' "$target"
"${here}/transfer-secrets.sh" "$target"

printf '==> copy first-boot.sh to %s:~/first-boot.sh\n' "$target"
scp -p "${here}/first-boot.sh" "${target}:first-boot.sh"
ssh "$target" "chmod 0755 first-boot.sh"

printf '==> run first-boot %s on %s\n' "$role" "$target"
printf '    finish the gh device login in the browser on this computer\n'
ssh -t "$target" "bash first-boot.sh ${role}"
