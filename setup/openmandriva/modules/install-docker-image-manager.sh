#!/usr/bin/env bash
# Placeholder for the still-undecided Docker image manager on one server
# (Portainer, Harbor, etc.). Run this module by hand on that box later.
#
#   ~/dot-files/setup/openmandriva/modules/install-docker-image-manager.sh

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user
log "docker image manager is not chosen yet; install docker only"
ensure_packages docker docker-compose
enable_service docker.service
warn "pick a manager and fill this module in; this script does not deploy one"
