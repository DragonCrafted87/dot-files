#!/usr/bin/env bash
# flight_fqdn and ensure_hostname promote an installer short name.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
unset REPO_ROOT DOTFILES_ROOT DOTFILES_LIB_LOADED
# shellcheck disable=SC1091
. "${HERE}/../lib/lib.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

expect_fqdn() {
    local input="$1" want="$2" got
    got="$(flight_fqdn "$input")"
    [[ "$got" == "$want" ]] || fail "flight_fqdn ${input} -> ${got}, want ${want}"
}

expect_die() {
    local input="$1" err rc
    err="${work}/die.err"
    set +e
    (
        flight_fqdn "$input" >"${work}/die.out" 2>"$err"
    )
    rc=$?
    set -e
    [[ "$rc" -ne 0 ]] || fail "flight_fqdn ${input:-empty} succeeded"
    [[ -s "$err" ]] || fail "flight_fqdn ${input:-empty} died without an error"
}

expect_fqdn runewyrm runewyrm.stealthdragonland.net
expect_fqdn runewyrm.stealthdragonland.net runewyrm.stealthdragonland.net
expect_fqdn runewyrm.lan runewyrm.stealthdragonland.net
expect_fqdn STUDY.LAN study.stealthdragonland.net
expect_fqdn faerie-dragon faerie-dragon.stealthdragonland.net
expect_die ""
expect_die localhost
expect_die localhost.localdomain
expect_die openmandriva
expect_die "-bad"
expect_die "has space"

long="$(printf 'a%.0s' {1..42})"
expect_fqdn "$long" "${long}.stealthdragonland.net"
longer="$(printf 'b%.0s' {1..43})"
expect_die "$longer"

saved_domain="${DOTFILES_DOMAIN}"
DOTFILES_DOMAIN="example.test"
expect_fqdn box box.example.test
DOTFILES_DOMAIN="$saved_domain"

hosts="${work}/hosts"
cat >"$hosts" <<'EOF'
# Standard host addresses
127.0.0.1  localhost
::1        localhost ip6-localhost ip6-loopback
# This host address
127.0.1.1  runewyrm
EOF
cp "$hosts" "${work}/hosts.orig"
hosts_with_short_name runewyrm "$hosts" >"${work}/hosts.out"
cmp -s "${work}/hosts.orig" "${work}/hosts.out" || fail "short hosts line was rewritten"

cat >"$hosts" <<'EOF'
# This host address
127.0.1.1  runewyrm.stealthdragonland.net runewyrm
127.0.1.1  extra
EOF
hosts_with_short_name runewyrm "$hosts" >"${work}/hosts.out"
grep -c '^127\.0\.1\.1' "${work}/hosts.out" | grep -qx 1 || fail "extra 127.0.1.1 lines remained"
grep -qx '127.0.1.1  runewyrm' "${work}/hosts.out" || fail "fqdn hosts line was not the short name"

cat >"$hosts" <<'EOF'
127.0.0.1  localhost
EOF
hosts_with_short_name study "$hosts" >"${work}/hosts.out"
grep -qx '127.0.0.1  localhost' "${work}/hosts.out" || fail "localhost line was dropped"
grep -qx '127.0.1.1  study' "${work}/hosts.out" || fail "missing 127.0.1.1 line was not added"

export DOTFILES_DRY_RUN=1
export HOSTS_FILE="${work}/live-hosts"
cat >"$HOSTS_FILE" <<'EOF'
127.0.0.1  localhost
127.0.1.1  runewyrm
EOF
cp "$HOSTS_FILE" "${work}/live-hosts.orig"

FAKE_STATIC="runewyrm"
hostnamectl() {
    if [[ "${1:-}" == "--static" ]]; then
        printf '%s\n' "$FAKE_STATIC"
        return 0
    fi
    printf 'unexpected hostnamectl %s\n' "$*" >&2
    return 1
}
sudo() {
    printf 'sudo was called: %s\n' "$*" >&2
    exit 99
}

ensure_hostname >"${work}/promote.out"
grep -F 'hostname runewyrm.stealthdragonland.net' "${work}/promote.out" >/dev/null \
    || fail "promote did not record the FQDN"
grep -F 'dry-run: sudo hostnamectl set-hostname runewyrm.stealthdragonland.net' "${work}/promote.out" >/dev/null \
    || fail "promote did not dry-run hostnamectl"
cmp -s "$HOSTS_FILE" "${work}/live-hosts.orig" || fail "promote rewrote a correct hosts line"

FAKE_STATIC="runewyrm.stealthdragonland.net"
ensure_hostname >"${work}/again.out"
[[ ! -s "${work}/again.out" ]] || fail "second run changed a finished hostname: $(cat "${work}/again.out")"

FAKE_STATIC="runewyrm"
ensure_hostname study.lan >"${work}/rename.out"
grep -F 'dry-run: sudo hostnamectl set-hostname study.stealthdragonland.net' "${work}/rename.out" >/dev/null \
    || fail "rename did not dry-run the new FQDN"
grep -F 'hosts ' "${work}/rename.out" >/dev/null || fail "rename did not update hosts"
grep -qx '127.0.1.1  runewyrm' "$HOSTS_FILE" || fail "dry-run rename wrote the hosts file"

(
    DOTFILES_DRY_RUN=0
    export HOSTS_FILE="${work}/write-hosts"
    printf '127.0.1.1  oldname\n' >"$HOSTS_FILE"
    ensure_hosts_short_name study >"${work}/write.out"
    grep -qx '127.0.1.1  study' "$HOSTS_FILE" || fail "hosts write left the old short name"
    [[ ! -e "${work}/.write-hosts.dotfiles-tmp" ]] || fail "hosts write left a temp file"
)

echo ok
