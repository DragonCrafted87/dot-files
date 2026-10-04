#!/bin/sh
# Replace /root/.ssh/authorized_keys with the keys listed on the GitHub
# account. Fails closed: a bad or empty fetch leaves the current file.
# Home Assistant OS has ash and curl. The root filesystem is erofs, so
# this copy stays POSIX and is installed under /mnt/overlay/dot-files.
# /root/.ssh is a persistent bind, and that is where the keys land.
#
#   GITHUB_KEYS_USER=DragonCrafted87 DOTFILES_HOME=/root ./haos-sync-github-keys.sh

set -eu

GITHUB_KEYS_USER="${GITHUB_KEYS_USER:-DragonCrafted87}"
DOTFILES_HOME="${DOTFILES_HOME:-/root}"
auth="${DOTFILES_HOME}/.ssh/authorized_keys"
url="https://github.com/${GITHUB_KEYS_USER}.keys"
key_re='^[A-Za-z0-9._+-]+(@openssh\.com)? [A-Za-z0-9+/=]+'

mkdir -p "${DOTFILES_HOME}/.ssh"
chmod 700 "${DOTFILES_HOME}/.ssh"

tmp="$(mktemp)"
out="${tmp}.out"
auth_tmp="${auth}.tmp"
trap 'rm -f "$tmp" "$out" "$auth_tmp"' EXIT

if ! curl -fsSL --max-time 20 "$url" -o "$tmp"; then
    printf 'error: failed to fetch %s\n' "$url" >&2
    exit 1
fi

if ! grep -qE "$key_re" "$tmp"; then
    printf 'error: %s did not contain any SSH public keys\n' "$url" >&2
    exit 1
fi

# BusyBox date has no --iso-8601. GNU date accepts this format too.
{
    printf '# synced from %s at %s\n' "$url" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    grep -E "$key_re" "$tmp"
} >"$out"

umask 077
cat "$out" >"$auth_tmp"
chmod 600 "$auth_tmp"
mv "$auth_tmp" "$auth"
printf 'updated %s from %s\n' "$auth" "$url"
