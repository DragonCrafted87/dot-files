#!/usr/bin/env bash
# Workstation Python tooling plus a reusable pre-commit container.
# The git init template lives in config/git/template and is linked into
# ~/.config/git by link-user-config.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

WRAPPER="${DOTFILES_HOME}/bin/pre-commit"
IMAGE_NAME="dotfiles-pre-commit"
DOCKERFILE="${SETUP_FILES_DIR}/pre-commit/Dockerfile"
CACHE_DIR="${DOTFILES_HOME}/.cache/pre-commit-docker"

ensure_packages python python-pip docker

if getent group docker >/dev/null 2>&1; then
    if ! id -nG "$DOTFILES_USER" | grep -qw docker; then
        log "add ${DOTFILES_USER} to docker"
        run sudo usermod -aG docker "$DOTFILES_USER"
    fi
fi

if command -v systemctl >/dev/null 2>&1; then
    enable_service docker.service || true
    if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
        sudo systemctl start docker.service 2>/dev/null || true
    fi
fi

ensure_dir "${DOTFILES_HOME}/.local"
ensure_dir "${DOTFILES_HOME}/bin"
ensure_dir "$CACHE_DIR"

if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
    log "would pip install --user wheel poetry python-dateutil requests"
else
    log "pip install --user wheel poetry python-dateutil requests"
    python -m pip install --user --upgrade pip wheel
    python -m pip install --user --upgrade poetry python-dateutil requests
fi

[[ -f "$DOCKERFILE" ]] || die "missing ${DOCKERFILE}"

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    log "build ${IMAGE_NAME}"
    run docker build -t "$IMAGE_NAME" "$(dirname "$DOCKERFILE")"
else
    warn "docker is not usable yet (group/session?); build ${IMAGE_NAME} after a re-login"
fi

run install -m 0755 "${SETUP_FILES_DIR}/pre-commit/pre-commit" "$WRAPPER"
