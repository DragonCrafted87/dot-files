#!/usr/bin/env bash
# Proves the haos role list skips [common] and saved subroles.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "${work}/config/dot-files"
printf 'laptop\n' >"${work}/config/dot-files/subroles"
printf 'workstation\n' >"${work}/config/dot-files/role"

unset REPO_ROOT DOTFILES_ROOT DOTFILES_LIB_LOADED
export REPO_ROOT="$repo"
export CONFIG_TARGET_DIR="${work}/config"
# shellcheck disable=SC1091
. "${repo}/setup/lib/lib.sh"

haos_list="$(role_modules haos)"
[[ "$haos_list" == "configure-haos" ]] || {
    printf 'expected only configure-haos, got:\n%s\n' "$haos_list" >&2
    exit 1
}

workstation_list="$(role_modules workstation)"
grep -qx 'bootstrap-tools' <<<"$workstation_list" || {
    printf 'workstation lost [common]:\n%s\n' "$workstation_list" >&2
    exit 1
}
grep -qx 'configure-laptop' <<<"$workstation_list" || {
    printf 'workstation lost the saved laptop subrole:\n%s\n' "$workstation_list" >&2
    exit 1
}

printf 'haos role list ok\n'

old_path="$PATH"
bin="${work}/bin"
mkdir -p "$bin"
ssh_log="${work}/ssh.log"
payload="${work}/payload"

cat >"${bin}/curl" <<'EOF'
#!/usr/bin/env bash
out=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o)
            out="$2"
            shift 2
            ;;
        -o*)
            out="${1#-o}"
            shift
            ;;
        *) shift ;;
    esac
done
emit() {
    if [[ -n "$out" ]]; then
        cat >"$out"
    else
        cat
    fi
}
case "${CURL_MODE:-ok}" in
    ok)
        printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey dragon@test' | emit
        ;;
    empty)
        : >"${out:-/dev/stdout}"
        ;;
    bad) printf '%s\n' 'not-a-key' | emit ;;
    fail) exit 1 ;;
    *) printf 'bad CURL_MODE %s\n' "${CURL_MODE}" >&2; exit 1 ;;
esac
EOF

cat >"${bin}/ssh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${SSH_LOG:?}"
case "${SSH_MODE:-fail}" in
    fail) exit 255 ;;
    notha) printf '%s\n' NOT-HAOS ;;
    ha)
        printf '%s\n' HAOS
        printf '%s\n' 'hostname: homeassistant'
        ;;
    *) printf 'bad SSH_MODE %s\n' "${SSH_MODE}" >&2; exit 1 ;;
esac
EOF
chmod 0755 "${bin}/curl" "${bin}/ssh"

run_haos() {
    env -u DOTFILES_DRY_RUN \
        PATH="${bin}:${old_path}" \
        REPO_ROOT="$repo" \
        HAOS_TARGET="root@192.0.2.51" \
        HAOS_HOSTNAME="ward-drake" \
        HAOS_CONFIG_DIR="$payload" \
        SSH_LOG="$ssh_log" \
        CURL_MODE="${CURL_MODE:-ok}" \
        SSH_MODE="${SSH_MODE:-fail}" \
        bash "${repo}/setup/modules/host/configure-haos.sh"
}

expect_keys='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey dragon@test'

: >"$ssh_log"
rm -rf "$payload"
mkdir -p "$payload"
printf 'KEEP\n' >"${payload}/authorized_keys"
CURL_MODE=empty
set +e
empty_out="$(run_haos 2>&1)"
empty_rc=$?
set -e
[[ "$empty_rc" -ne 0 ]] || {
    printf 'empty key fetch should fail:\n%s\n' "$empty_out" >&2
    exit 1
}
[[ "$(cat "${payload}/authorized_keys")" == "KEEP" ]] || {
    printf 'empty fetch replaced the payload:\n%s\n' "$(cat "${payload}/authorized_keys")" >&2
    exit 1
}
[[ ! -s "$ssh_log" ]] || {
    printf 'empty fetch talked to ssh:\n%s\n' "$(cat "$ssh_log")" >&2
    exit 1
}

: >"$ssh_log"
CURL_MODE=bad
set +e
bad_out="$(run_haos 2>&1)"
bad_rc=$?
set -e
[[ "$bad_rc" -ne 0 ]] || {
    printf 'non-key fetch should fail:\n%s\n' "$bad_out" >&2
    exit 1
}
[[ "$(cat "${payload}/authorized_keys")" == "KEEP" ]] || {
    printf 'non-key fetch replaced the payload\n' >&2
    exit 1
}

: >"$ssh_log"
CURL_MODE=fail
set +e
fail_fetch_out="$(run_haos 2>&1)"
fail_fetch_rc=$?
set -e
[[ "$fail_fetch_rc" -ne 0 ]]
[[ "$(cat "${payload}/authorized_keys")" == "KEEP" ]] || {
    printf 'failed fetch replaced the payload:\n%s\n' "$fail_fetch_out" >&2
    exit 1
}

: >"$ssh_log"
rm -rf "$payload"
CURL_MODE=ok
SSH_MODE=fail
set +e
ssh_fail_out="$(run_haos 2>&1)"
ssh_fail_rc=$?
set -e
[[ "$ssh_fail_rc" -ne 0 ]] || {
    printf 'ssh failure should stop:\n%s\n' "$ssh_fail_out" >&2
    exit 1
}
[[ "$(cat "${payload}/authorized_keys")" == "$expect_keys" ]] || {
    printf 'payload keys:\n%s\n' "$(cat "${payload}/authorized_keys")" >&2
    exit 1
}
if grep -q 'host options' "$ssh_log"; then
    printf 'ssh failure sent a hostname command:\n%s\n' "$(cat "$ssh_log")" >&2
    exit 1
fi

: >"$ssh_log"
rm -rf "$payload"
mkdir -p "$payload"
printf 'KEEP\n' >"${payload}/authorized_keys"
SSH_MODE=notha
set +e
notha_out="$(run_haos 2>&1)"
notha_rc=$?
set -e
[[ "$notha_rc" -ne 0 ]] || {
    printf 'non-HA target should be refused:\n%s\n' "$notha_out" >&2
    exit 1
}
[[ "$(cat "${payload}/authorized_keys")" == "KEEP" ]] || {
    printf 'non-HA target changed the payload\n' >&2
    exit 1
}
if grep -q 'host options' "$ssh_log"; then
    printf 'non-HA target sent a hostname command:\n%s\n' "$(cat "$ssh_log")" >&2
    exit 1
fi

: >"$ssh_log"
rm -rf "$payload"
SSH_MODE=ha
set +e
ha_out="$(run_haos 2>&1)"
ha_rc=$?
set -e
[[ "$ha_rc" -eq 0 ]] || {
    printf 'HA target failed:\n%s\n' "$ha_out" >&2
    exit 1
}
first="$(head -n 1 "$ssh_log")"
[[ "$first" == *"command -v ha"* ]] || {
    printf 'first ssh was not the probe:\n%s\n' "$first" >&2
    exit 1
}
[[ "$first" != *"host options"* ]] || {
    printf 'hostname was sent before the probe:\n%s\n' "$first" >&2
    exit 1
}
grep -q 'ha host options --hostname ward-drake' "$ssh_log" || {
    printf 'hostname command missing:\n%s\n' "$(cat "$ssh_log")" >&2
    exit 1
}

printf 'haos module ok\n'

hostctl_log="${work}/hostnamectl.log"
: >"$hostctl_log"
cat >"${bin}/hostnamectl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${HOSTNAMECTL_LOG:?}"
exit 99
EOF
chmod 0755 "${bin}/hostnamectl"

real_role="${HOME}/.config/dot-files/role"
role_before="$(cat "$real_role")"
host_before="$(/usr/bin/hostnamectl --static)"

run_role() {
    env -u CONFIG_TARGET_DIR -u HAOS_TARGET -u HAOS_HOSTNAME \
        PATH="${bin}:${old_path}" \
        REPO_ROOT="$repo" \
        HOSTNAMECTL_LOG="$hostctl_log" \
        bash "${repo}/setup/role.sh" "$@"
}

assert_operator_unchanged() {
    local label="$1"
    [[ "$(cat "$real_role")" == "$role_before" ]] || {
        printf '%s changed the saved role to %s\n' "$label" "$(cat "$real_role")" >&2
        exit 1
    }
    [[ "$(/usr/bin/hostnamectl --static)" == "$host_before" ]] || {
        printf '%s changed the local hostname\n' "$label" >&2
        exit 1
    }
    [[ ! -s "$hostctl_log" ]] || {
        printf '%s called hostnamectl:\n%s\n' "$label" "$(cat "$hostctl_log")" >&2
        exit 1
    }
}

: >"$hostctl_log"
set +e
no_target_out="$(run_role haos 2>&1)"
no_target_rc=$?
set -e
[[ "$no_target_rc" -ne 0 ]] || {
    printf 'haos without --target should fail:\n%s\n' "$no_target_out" >&2
    exit 1
}
grep -q -- '--target' <<<"$no_target_out" || {
    printf 'missing --target error:\n%s\n' "$no_target_out" >&2
    exit 1
}
assert_operator_unchanged "no-target"

: >"$hostctl_log"
set +e
reset_out="$(run_role --reset haos 2>&1)"
reset_rc=$?
set -e
[[ "$reset_rc" -ne 0 ]] || {
    printf 'haos --reset should fail:\n%s\n' "$reset_out" >&2
    exit 1
}
grep -q 'haos does not use --reset' <<<"$reset_out" || {
    printf 'haos --reset reached the local reset flow:\n%s\n' "$reset_out" >&2
    exit 1
}
assert_operator_unchanged "reset"

: >"$hostctl_log"
set +e
dry_out="$(run_role --dry-run --target root@192.0.2.51 haos 2>&1)"
dry_rc=$?
set -e
[[ "$dry_rc" -eq 0 ]] || {
    printf 'haos dry-run failed:\n%s\n' "$dry_out" >&2
    exit 1
}
grep -q '22222' <<<"$dry_out" || {
    printf 'dry-run missing port 22222:\n%s\n' "$dry_out" >&2
    exit 1
}
grep -q 'ha host options --hostname ward-drake' <<<"$dry_out" || {
    printf 'dry-run missing hostname command:\n%s\n' "$dry_out" >&2
    exit 1
}
if grep -q 'hostnamectl' <<<"$dry_out"; then
    printf 'dry-run mentioned hostnamectl:\n%s\n' "$dry_out" >&2
    exit 1
fi
assert_operator_unchanged "dry-run"

printf 'haos role.sh ok\n'

gh_log="${work}/gh.log"
: >"$gh_log"
: >"$ssh_log"
cat >"${bin}/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${GH_LOG:?}"
exit 0
EOF
chmod 0755 "${bin}/gh"

set +e
init_out="$(
    env PATH="${bin}:${old_path}" \
        GH_LOG="$gh_log" \
        SSH_LOG="$ssh_log" \
        bash "${repo}/setup/init-remote.sh" root@192.0.2.51 haos 2>&1
)"
init_rc=$?
set -e
[[ "$init_rc" -ne 0 ]] || {
    printf 'init-remote haos should fail:\n%s\n' "$init_out" >&2
    exit 1
}
grep -q 'role.sh --target' <<<"$init_out" || {
    printf 'init-remote missing role.sh --target pointer:\n%s\n' "$init_out" >&2
    exit 1
}
[[ ! -s "$ssh_log" ]] || {
    printf 'init-remote opened ssh:\n%s\n' "$(cat "$ssh_log")" >&2
    exit 1
}

ssh_g="$(ssh -G ward-drake)"
grep -qx 'user root' <<<"$ssh_g" || {
    printf 'ssh -G ward-drake user:\n%s\n' "$ssh_g" >&2
    exit 1
}
grep -qx 'port 22222' <<<"$ssh_g" || {
    printf 'ssh -G ward-drake port:\n%s\n' "$ssh_g" >&2
    exit 1
}

printf 'haos init-remote and ssh config ok\n'
