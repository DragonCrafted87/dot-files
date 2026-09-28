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
