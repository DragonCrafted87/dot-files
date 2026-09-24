#!/usr/bin/env bash
# Artifact repo manager subrole. Starts as a Docker host so this box can
# later hold an image registry, an OpenMandriva dnf cache, and on-disk
# AI model blobs. Those extra stores are not installed here yet.
#
#   ~/dot-files/setup/role.sh --enable-subrole artifact-repo

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib.sh"

require_user

log "artifact repo manager: install docker runtime"
ensure_packages docker docker-compose
enable_service docker.service
if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
    run sudo systemctl start docker.service || warn "could not start docker.service"
fi

store="${ARTIFACT_REPO_ROOT:-/srv/artifact-repo}"
if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
    log "dry-run: mkdir -p ${store}/{docker,dnf,models}"
else
    run sudo mkdir -p "${store}/docker" "${store}/dnf" "${store}/models"
    run sudo chown "${DOTFILES_USER}:${DOTFILES_USER}" "$store" \
        "${store}/docker" "${store}/dnf" "${store}/models"
fi

readme="${store}/README"
readme_body="artifact-repo layout for $(hostname -s)
docker/  local image store / future registry data
dnf/     planned OpenMandriva dnf cache passthrough
models/  planned AI model blobs
"
if [[ -w "$(dirname "$readme")" || -w "$store" ]]; then
    ensure_file_contents "$readme" "$readme_body"
elif [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
    log "write ${readme}"
    printf '%s\n' "$readme_body" | run sudo tee "$readme" >/dev/null
    run sudo chown "${DOTFILES_USER}:${DOTFILES_USER}" "$readme"
fi

log "artifact repo root ${store}"
warn "dnf cache passthrough and model store are not wired yet"
warn "docker image UI (Harbor, Portainer, ...) is not chosen yet"
