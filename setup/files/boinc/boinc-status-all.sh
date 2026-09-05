#!/usr/bin/env bash
# Show status for every host in hosts.list.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=find-boinccmd.sh
. "${HERE}/find-boinccmd.sh"
