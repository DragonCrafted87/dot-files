#!/usr/bin/env bash
# Run on the new machine. Prefer init-remote.sh from a working computer
# instead of copying this file by hand.
#
#   ./setup/openmandriva/init-remote.sh dragon@newbox.lan workstation
#
# Generates an SSH key, attaches it to GitHub via gh's device login,
# clones the repo over SSH, then runs the chosen role.

set -euo pipefail

DOTFILES_USER="${DOTFILES_USER:-dragon}"
DOTFILES_HOME="${DOTFILES_HOME:-/home/${DOTFILES_USER}}"
DOTFILES_DIR="${DOTFILES_DIR:-${DOTFILES_HOME}/dot-files}"
DOTFILES_REPO_URL="${DOTFILES_REPO_URL:-git@github.com:DragonCrafted87/dot-files.git}"
SSH_KEY_PATH="${SSH_KEY_PATH:-${DOTFILES_HOME}/.ssh/id_ed25519}"
role="${1:-}"

if [[ "$(id -un)" != "${DOTFILES_USER}" ]]; then
    printf 'error: run this as %s, not %s\n' "${DOTFILES_USER}" "$(id -un)" >&2
    exit 1
fi

if [[ -z "$role" ]]; then
    printf 'usage: %s workstation|laptop|htpc|server\n' "$0" >&2
    exit 1
fi

printf '==> install bootstrap packages\n'
sudo dnf install -y git curl gh

mkdir -p "${DOTFILES_HOME}/.ssh"
chmod 700 "${DOTFILES_HOME}/.ssh"

if [[ ! -f "${SSH_KEY_PATH}" ]]; then
    printf '==> generate %s\n' "${SSH_KEY_PATH}"
    ssh-keygen -t ed25519 -f "${SSH_KEY_PATH}" -C "${DOTFILES_USER}@$(hostname -s)" -N ""
    chmod 600 "${SSH_KEY_PATH}"
    chmod 644 "${SSH_KEY_PATH}.pub"
fi

printf '==> public key:\n'
cat "${SSH_KEY_PATH}.pub"
printf '\n'

if ! gh auth status --hostname github.com >/dev/null 2>&1; then
    printf '==> log in to GitHub with the device code on your working computer\n'
    gh auth login --hostname github.com --git-protocol ssh --web
fi

pubkey="$(awk '{print $2}' "${SSH_KEY_PATH}.pub")"
if gh ssh-key list 2>/dev/null | grep -Fq "$pubkey"; then
    printf '==> ssh key already registered on GitHub\n'
else
    title="$(hostname -s)-$(date +%Y%m%d)"
    printf '==> add ssh key to GitHub as %s\n' "$title"
    gh ssh-key add "${SSH_KEY_PATH}.pub" --title "$title"
fi

if [[ ! -d "${DOTFILES_DIR}/.git" ]]; then
    printf '==> clone %s -> %s\n' "${DOTFILES_REPO_URL}" "${DOTFILES_DIR}"
    git clone "${DOTFILES_REPO_URL}" "${DOTFILES_DIR}"
fi

role_script="${DOTFILES_DIR}/setup/openmandriva/${role}.sh"
if [[ ! -f "$role_script" ]]; then
    printf 'error: unknown role %s (%s missing)\n' "$role" "$role_script" >&2
    exit 1
fi

exec "$role_script"
