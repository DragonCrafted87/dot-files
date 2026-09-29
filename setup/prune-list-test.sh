#!/usr/bin/env bash
# Prove list-only prune finds the ISO list and does not remove packages.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
py="${repo}/setup/modules/common/prune-extra-packages.py"
log="$(mktemp)"
bindir="$(mktemp -d)"
trap 'rm -rf "$bindir" "$log"' EXIT

cat >"${bindir}/dnf" <<'EOF'
#!/bin/sh
printf 'dnf %s\n' "$*" >>"${DNF_LOG:?}"
exit 99
EOF
cat >"${bindir}/flatpak" <<'EOF'
#!/bin/sh
printf 'flatpak %s\n' "$*" >>"${DNF_LOG:?}"
exit 0
EOF
cat >"${bindir}/rpm" <<'EOF'
#!/bin/sh
printf 'bash\nextra-demo-pkg\n'
EOF
chmod 755 "${bindir}/dnf" "${bindir}/flatpak" "${bindir}/rpm"

DNF_LOG="$log" PATH="${bindir}:${PATH}" python3 "$py" >"${log}.out" 2>"${log}.err" || true
grep -q 'iso-installed.txt' "${log}.out"
grep -q 'extra-demo-pkg' "${log}.out"
if grep -q '^dnf ' "$log"; then
    printf 'dnf was invoked during list-only\n' >&2
    exit 1
fi
if grep -q 'flatpak uninstall' "$log"; then
    printf 'flatpak uninstall was invoked during list-only\n' >&2
    exit 1
fi
printf 'prune list-only ok\n'

# Boot remove must keep flatpak uninstall's status. Stubs never call real sudo.
run_flatpak_case() {
    local uninstall_rc="$1" expect_rc="$2"
    local case_dir="${bindir}/flatpak-${uninstall_rc}"
    local sudo_log="${case_dir}/sudo.log"
    local dnf_log="${case_dir}/dnf.log"
    mkdir -p "$case_dir"
    : >"$sudo_log"
    : >"$dnf_log"
    cat >"${case_dir}/sudo" <<'EOF'
#!/bin/sh
# Test stub. Never exec /usr/bin/sudo.
printf '%s\n' "$*" >>"${SUDO_LOG:?}"
if [ "$1" = flatpak ]; then
    shift
    flatpak "$@"
    exit $?
fi
printf 'unexpected sudo command: %s\n' "$*" >&2
exit 97
EOF
    cat >"${case_dir}/flatpak" <<'EOF'
#!/bin/sh
case "$1" in
    list)
        printf '%s\n' 'org.example.Demo'
        exit 0
        ;;
    uninstall)
        exit "${FLATPAK_UNINSTALL_RC:?}"
        ;;
esac
exit 0
EOF
    cat >"${case_dir}/rpm" <<'EOF'
#!/bin/sh
printf 'bash\n'
exit 0
EOF
    cat >"${case_dir}/dnf" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${DNF_LOG:?}"
exit 99
EOF
    chmod 755 "${case_dir}/sudo" "${case_dir}/flatpak" "${case_dir}/rpm" \
        "${case_dir}/dnf"
    local out="${case_dir}/out" err="${case_dir}/err" rc
    set +e
    SUDO_LOG="$sudo_log" DNF_LOG="$dnf_log" FLATPAK_UNINSTALL_RC="$uninstall_rc" \
        RESET_CONFIRM=yes RESET_FROM_BOOT=1 \
        PATH="${case_dir}:${PATH}" \
        python3 "$py" >"$out" 2>"$err"
    rc=$?
    set -e
    if [[ "$rc" -ne "$expect_rc" ]]; then
        printf 'flatpak uninstall rc %s: expected exit %s, got %s\n' \
            "$uninstall_rc" "$expect_rc" "$rc" >&2
        cat "$out" >&2
        cat "$err" >&2
        exit 1
    fi
    if ! grep -q 'flatpak' "$sudo_log" || ! grep -q 'uninstall' "$sudo_log"; then
        printf 'sudo stub did not see flatpak uninstall\n' >&2
        cat "$sudo_log" >&2
        exit 1
    fi
    if grep -q 'dnf' "$sudo_log" || [[ -s "$dnf_log" ]]; then
        printf 'dnf remove ran with an empty remove set\n' >&2
        cat "$sudo_log" >&2
        cat "$dnf_log" >&2
        exit 1
    fi
}

run_flatpak_case 1 1
run_flatpak_case 0 0
printf 'prune flatpak status ok\n'
