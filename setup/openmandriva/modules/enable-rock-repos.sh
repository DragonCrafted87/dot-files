#!/usr/bin/env bash
# Enable Rock extra / restricted / non-free for this machine's package
# architecture (znver1 or x86_64). Fresh installs only ship main.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

rpm_arch="$(detect_omv_repo_arch)"
case "$rpm_arch" in
    znver1 | x86_64 | aarch64) ;;
    *)
        warn "unexpected repo arch ${rpm_arch}; falling back to x86_64"
        rpm_arch="x86_64"
        ;;
esac
log "cpu vendor/family selected repo arch ${rpm_arch} (rpm %{_arch}=$(rpm --eval '%{_arch}'))"

channel="rock"
if dnf repolist --enabled 2>/dev/null | awk '{print $1}' | grep -q '^rolling'; then
    channel="rolling"
elif dnf repolist --enabled 2>/dev/null | awk '{print $1}' | grep -q '^cooker'; then
    channel="cooker"
fi

log "enable ${channel} repos for ${rpm_arch}"

ids=("${channel}-${rpm_arch}")
if [[ "$channel" == "rock" || "$channel" == "release" ]]; then
    ids+=(
        "${channel}-updates-${rpm_arch}"
        "${channel}-${rpm_arch}-extra"
        "${channel}-updates-${rpm_arch}-extra"
        "${channel}-${rpm_arch}-restricted"
        "${channel}-updates-${rpm_arch}-restricted"
        "${channel}-${rpm_arch}-non-free"
        "${channel}-updates-${rpm_arch}-non-free"
    )
else
    ids+=(
        "${channel}-${rpm_arch}-extra"
        "${channel}-${rpm_arch}-restricted"
        "${channel}-${rpm_arch}-non-free"
    )
fi

other="x86_64"
if [[ "$rpm_arch" == "x86_64" ]]; then
    other="znver1"
fi

if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
    printf 'dry-run: dnf config-manager --set-enabled %s\n' "${ids[*]}"
    printf 'dry-run: dnf config-manager --set-disabled %s-%s*\n' "$channel" "$other"
    exit 0
fi

sudo dnf config-manager --set-enabled "${ids[@]}" || sudo dnf config-manager --enable "${ids[@]}"

# Do not mix znver1 and generic x86_64 package sets.
mapfile -t other_ids < <(dnf repolist --all 2>/dev/null | awk '{print $1}' | grep -E "^${channel}(-updates)?-${other}" || true)
if [[ "${#other_ids[@]}" -gt 0 ]]; then
    log "disable opposite-arch repos: ${other_ids[*]}"
    sudo dnf config-manager --set-disabled "${other_ids[@]}" || sudo dnf config-manager --disable "${other_ids[@]}" || true
fi
