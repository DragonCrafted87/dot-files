#!/usr/bin/env bash
# Replace ~/.ssh/authorized_keys with the keys listed on the GitHub
# account. Fails closed: a bad or empty fetch leaves the current file.
#
#   GITHUB_KEYS_USER=DragonCrafted87 ./sync-github-authorized-keys.sh

set -euo pipefail

GITHUB_KEYS_USER="${GITHUB_KEYS_USER:-DragonCrafted87}"
DOTFILES_USER="${DOTFILES_USER:-dragon}"
DOTFILES_HOME="${DOTFILES_HOME:-/home/${DOTFILES_USER}}"
auth="${DOTFILES_HOME}/.ssh/authorized_keys"
url="https://github.com/${GITHUB_KEYS_USER}.keys"

mkdir -p "${DOTFILES_HOME}/.ssh"
chmod 700 "${DOTFILES_HOME}/.ssh"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

if ! curl -fsSL --max-time 20 "$url" -o "$tmp"; then
    printf 'error: failed to fetch %s\n' "$url" >&2
    exit 1
fi

if ! grep -qE '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|sk-ssh-ed25519) ' "$tmp"; then
    printf 'error: %s did not contain any SSH public keys\n' "$url" >&2
    exit 1
fi

{
    printf '# synced from %s at %s\n' "$url" "$(date --iso-8601=seconds)"
    grep -E '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|sk-ssh-ed25519) ' "$tmp"
} >"${tmp}.out"

install -m 0600 "${tmp}.out" "$auth"
chown "${DOTFILES_USER}:${DOTFILES_USER}" "$auth" 2>/dev/null || true
rm -f "${tmp}.out"
printf 'updated %s from %s\n' "$auth" "$url"
