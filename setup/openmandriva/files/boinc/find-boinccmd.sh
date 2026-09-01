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
    if command -v rpm >/dev/null 2>&1; then
        candidate="$(rpm -ql boinc-client 2>/dev/null | grep -E '/boinccmd$' | head -n1 || true)"
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    fi
    return 1
}

BOINCCMD="$(find_boinccmd || true)"
if [[ -z "${BOINCCMD}" ]]; then
    printf 'error: boinccmd not found; rpm -ql boinc-client | grep bin\n' >&2
    exit 1
fi
PATH="$(dirname "${BOINCCMD}"):${PATH}"
export PATH BOINCCMD
