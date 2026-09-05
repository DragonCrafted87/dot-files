#!/usr/bin/env bash
# shellcheck shell=bash
# Resolve boinccmd after the official Fedora RPM install.

find_boinccmd() {
    local candidate
    for candidate in \
        /usr/bin/boinccmd \
        /usr/local/bin/boinccmd \
        /usr/libexec/boinc/boinccmd \
        /usr/lib/boinc/boinccmd
    do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    if command -v boinccmd >/dev/null 2>&1; then
        command -v boinccmd
        return 0
    fi
    return 1
}
