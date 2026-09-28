#!/usr/bin/env bash
# Shared helpers for setup modules and role scripts.
# Safe to source more than once.
# This is the only import. Pieces live beside this file.

# shellcheck disable=SC2034

if [[ -n "${DOTFILES_LIB_LOADED:-}" ]]; then
    return 0
fi
DOTFILES_LIB_LOADED=1

set -euo pipefail

log() {
    printf '==> %s\n' "$*"
}

warn() {
    printf 'warning: %s\n' "$*" >&2
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

run() {
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        printf 'dry-run: %s\n' "$*"
        return 0
    fi
    "$@"
}

_git_toplevel() {
    git -C "$1" rev-parse --show-toplevel 2>/dev/null || return 1
}

# Saved clone path wins. REPO_ROOT and DOTFILES_ROOT name the same tree.
if [[ -z "${REPO_ROOT:-}" && -n "${DOTFILES_ROOT:-}" ]]; then
    REPO_ROOT="$DOTFILES_ROOT"
fi

_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${SETUP_DIR:-}" ]]; then
    SETUP_DIR="$(cd "${_lib_dir}/.." && pwd)"
fi

# Never use bare `git rev-parse` — modules are often run from $HOME.
if [[ -z "${REPO_ROOT:-}" ]]; then
    REPO_ROOT="$(_git_toplevel "$SETUP_DIR" || true)"
fi
if [[ -z "${REPO_ROOT:-}" ]]; then
    REPO_ROOT="$(_git_toplevel "$(dirname "$SETUP_DIR")" || true)"
fi
if [[ -z "${REPO_ROOT:-}" && -d "${SETUP_DIR}/../bashrc.d" ]]; then
    REPO_ROOT="$(cd "${SETUP_DIR}/.." && pwd)"
fi

DOTFILES_USER="${DOTFILES_USER:-dragon}"
DOTFILES_HOME="${DOTFILES_HOME:-/home/${DOTFILES_USER}}"
DOTFILES_DIR="${DOTFILES_DIR:-${DOTFILES_HOME}/dot-files}"

if [[ -z "${REPO_ROOT:-}" && -d "${DOTFILES_DIR}/.git" ]]; then
    REPO_ROOT="$(_git_toplevel "$DOTFILES_DIR" || printf '%s' "$DOTFILES_DIR")"
fi
if [[ -z "${REPO_ROOT:-}" ]]; then
    die "cannot find the dot-files repo root from ${SETUP_DIR} (cwd=$(pwd))"
fi

export REPO_ROOT
if [[ -z "${DOTFILES_ROOT:-}" ]]; then
    DOTFILES_ROOT="$REPO_ROOT"
fi
export DOTFILES_ROOT
SETUP_DIR="${REPO_ROOT}/setup"

require_user() {
    if [[ "$(id -un)" != "${DOTFILES_USER}" ]]; then
        die "run this as ${DOTFILES_USER}, not $(id -un)"
    fi
}

DOTFILES_REPO_URL="${DOTFILES_REPO_URL:-git@github.com:DragonCrafted87/dot-files.git}"
SSH_KEY_PATH="${SSH_KEY_PATH:-${DOTFILES_HOME}/.ssh/id_ed25519}"
DOTFILES_BASHRC="${DOTFILES_BASHRC:-hw_bashrc.sh}"
DOTFILES_TIMEZONE="${DOTFILES_TIMEZONE:-America/Chicago}"
OMP_INSTALL_DIR="${OMP_INSTALL_DIR:-${DOTFILES_HOME}/bin}"
CONFIG_SOURCE_DIR="${CONFIG_SOURCE_DIR:-${REPO_ROOT}/config}"
CONFIG_TARGET_DIR="${CONFIG_TARGET_DIR:-${DOTFILES_HOME}/.config}"
SETUP_FILES_DIR="${SETUP_FILES_DIR:-${SETUP_DIR}/files}"
SETUP_VERSIONS_FILE="${SETUP_VERSIONS_FILE:-${SETUP_DIR}/versions.conf}"
COMPILER_ENV_FILE="${COMPILER_ENV_FILE:-${REPO_ROOT}/bashrc.d/compiler.bashrc}"
# Cross-module flags belong in /tmp, not ~/.config/dot-files.
DOTFILES_QS_RESTART_FLAG="${DOTFILES_QS_RESTART_FLAG:-/tmp/dot-files-$(id -u)-need-qs-restart}"

_dotfiles_source() {
    local name="$1"
    # shellcheck disable=SC1090
    . "${REPO_ROOT}/setup/lib/${name}.sh"
}

_dotfiles_source files
_dotfiles_source packages
_dotfiles_source services
_dotfiles_source desktop
_dotfiles_source roles
# shellcheck disable=SC1091
. "${REPO_ROOT}/setup/subroles.sh"
unset -f _dotfiles_source

load_source_versions
load_compiler_env
