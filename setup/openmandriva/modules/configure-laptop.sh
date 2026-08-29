#!/usr/bin/env bash
# Laptop-only steps.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user
ensure_packages power-profiles-daemon
enable_service power-profiles-daemon.service
