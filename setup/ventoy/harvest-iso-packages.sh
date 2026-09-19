#!/usr/bin/env bash
# Dump the package names the current system (live ISO or installed root)
# has installed. Run this ON the live image, then copy the file off.
#
#   sudo bash harvest-iso-packages.sh > iso-installed.txt
#   sudo bash harvest-iso-packages.sh /tmp/iso-installed.txt
#
# Commit the result as setup/files/packages/iso-installed.list so
# prune-extra-packages can treat ISO packages as the baseline instead of
# a growing never-remove list.

set -euo pipefail

out="${1:-/dev/stdout}"

{
    printf '# harvested %s\n' "$(date -Iseconds)"
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        printf '# os=%s version=%s\n' "${NAME:-unknown}" "${VERSION_ID:-unknown}"
    fi
    printf '# source=rpm -qa --qf %%{name}\n'
    rpm -qa --qf '%{name}\n' | sort -u
} >"$out"

if [[ "$out" != /dev/stdout ]]; then
    printf 'wrote %s (%s names)\n' "$out" "$(grep -cvE '^#' "$out")" >&2
fi
