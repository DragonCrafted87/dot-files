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
ssh_state="${work}/ssh.state"
ssh_stdin="${work}/ssh.stdin"
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
is_probe=0
is_install=0
[[ "$*" == *"command -v ha"* ]] && is_probe=1
[[ "$*" == *"authorized_keys"* ]] && is_install=1

accept_rest() {
    local cmd="$1"
    local dest base
    if [[ "$is_probe" -eq 1 ]]; then
        printf '%s\n' HAOS
        exit 0
    fi
    if [[ "$cmd" == *"cat > "* ]]; then
        dest="$(printf '%s\n' "$cmd" | sed -n 's/.*cat > \([^ ]*\).*/\1/p')"
        base="$(basename "$dest")"
        if [[ -n "${SSH_CAPTURE:-}" && -n "$base" ]]; then
            mkdir -p "$SSH_CAPTURE"
            cat >"${SSH_CAPTURE}/${base}"
        else
            cat >/dev/null
        fi
        exit 0
    fi
    if [[ "$is_install" -eq 1 ]]; then
        cat >/dev/null
    fi
    exit 0
}

case "${SSH_MODE:-fail}" in
    fail)
        printf '%s\n' 'ssh: connect to host port 22222: Connection refused' >&2
        exit 255
        ;;
    remote)
        printf '%s\n' 'remote command failed' >&2
        exit 1
        ;;
    hostkey)
        printf '%s\n' 'WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!' >&2
        exit 255
        ;;
    installfail)
        if [[ "$is_install" -eq 1 ]]; then
            cat >/dev/null
            exit 1
        fi
        if [[ "$is_probe" -eq 1 ]]; then
            printf '%s\n' HAOS
            exit 0
        fi
        exit 1
        ;;
    denied)
        printf '%s\n' 'Permission denied (publickey).' >&2
        exit 255
        ;;
    syncfail)
        if [[ "$*" == *"/mnt/overlay/dot-files/sync-github-keys.sh"* ]]; then
            printf '%s\n' 'failed to write sync script' >&2
            exit 1
        fi
        accept_rest "$*"
        ;;
    syncwarn)
        if [[ "$*" == *"/mnt/overlay/dot-files/sync-github-keys.sh"* && "$*" != *"cat > "* ]]; then
            printf '%s\n' 'error: failed to fetch' >&2
            exit 1
        fi
        accept_rest "$*"
        ;;
    lockfail)
        if [[ "$*" == *"haos-activate.sh"* && "$*" != *"cat > "* ]]; then
            printf '%s\n' 'Failed to mask ha-cli@tty1.service' >&2
            exit 1
        fi
        accept_rest "$*"
        ;;
    notha) printf '%s\n' NOT-HAOS ;;
    ha) accept_rest "$*" ;;
    *) printf 'bad SSH_MODE %s\n' "${SSH_MODE}" >&2; exit 1 ;;
esac
EOF
chmod 0755 "${bin}/curl" "${bin}/ssh"

ssh_capture="${work}/ssh-capture"

run_haos() {
    env -u DOTFILES_DRY_RUN \
        PATH="${bin}:${old_path}" \
        REPO_ROOT="$repo" \
        HAOS_TARGET="root@192.0.2.51" \
        HAOS_HOSTNAME="ward-drake" \
        HAOS_CONFIG_DIR="$payload" \
        SSH_LOG="$ssh_log" \
        SSH_STATE="$ssh_state" \
        SSH_STDIN="$ssh_stdin" \
        SSH_CAPTURE="$ssh_capture" \
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
if grep -q 'PreferredAuthentications=password' "$ssh_log"; then
    printf 'closed port asked for a password:\n%s\n' "$(cat "$ssh_log")" >&2
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
rm -rf "$payload" "$ssh_capture"
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
grep -q 'authorized_keys' "$ssh_log" || {
    printf 'key login did not install authorized_keys:\n%s\n' "$(cat "$ssh_log")" >&2
    exit 1
}
if grep -q 'addons/self' "$ssh_log"; then
    printf 'key login talked to the SSH app:\n%s\n' "$(cat "$ssh_log")" >&2
    exit 1
fi
grep -q 'installed SSH keys' <<<"$ha_out" || {
    printf 'key login did not report the host keys:\n%s\n' "$ha_out" >&2
    exit 1
}
grep -q 'installed the HAOS updater' <<<"$ha_out" || {
    printf 'key login did not report the updater:\n%s\n' "$ha_out" >&2
    exit 1
}
grep -q '/mnt/overlay/dot-files/haos-activate.sh' "$ssh_log" || {
    printf 'key login did not activate the supervisor:\n%s\n' "$(cat "$ssh_log")" >&2
    exit 1
}
grep -q 'ForwardX11=no' "$ssh_log" || {
    printf 'key login forwarded X11:\n%s\n' "$(cat "$ssh_log")" >&2
    exit 1
}
if grep -q '/root/bin\|/etc/systemd/system\|sync-github-keys.timer\|systemctl start getty' "$ssh_log"; then
    printf 'key login used a read-only path or a getty:\n%s\n' "$(cat "$ssh_log")" >&2
    exit 1
fi
grep -q 'locked the console' <<<"$ha_out" || {
    printf 'key login did not report the console lock:\n%s\n' "$ha_out" >&2
    exit 1
}
grep -q '^#!/bin/sh' "${ssh_capture}/sync-github-keys.sh" || {
    printf 'captured updater is not a /bin/sh script\n' >&2
    exit 1
}
grep -q 'DOTFILES_HOME:-/root' "${ssh_capture}/sync-github-keys.sh" || {
    printf 'captured updater does not write /root:\n%s\n' "$(cat "${ssh_capture}/sync-github-keys.sh")" >&2
    exit 1
}
grep -q '^keys_user=DragonCrafted87$' "${ssh_capture}/haos-supervise.sh" || {
    printf 'captured supervisor lost the GitHub user:\n%s\n' "$(cat "${ssh_capture}/haos-supervise.sh")" >&2
    exit 1
}
grep -q 'sleep 43200' "${ssh_capture}/haos-supervise.sh" || {
    printf 'captured supervisor cadence:\n%s\n' "$(cat "${ssh_capture}/haos-supervise.sh")" >&2
    exit 1
}
grep -q 'mask --runtime --now ha-cli@tty1.service getty@tty1.service' "${ssh_capture}/haos-supervise.sh" || {
    printf 'captured supervisor does not mask tty1:\n%s\n' "$(cat "${ssh_capture}/haos-supervise.sh")" >&2
    exit 1
}
if grep -q '^User=' "${ssh_capture}/haos-supervise.sh"; then
    printf 'captured supervisor sets a user:\n%s\n' "$(cat "${ssh_capture}/haos-supervise.sh")" >&2
    exit 1
fi
grep -q 'systemd.mask=ha-cli@tty1.service' "${ssh_capture}/haos-activate.sh" || {
    printf 'captured activate script misses the ha-cli mask\n' >&2
    exit 1
}
grep -q 'systemd.mask=getty@tty1.service' "${ssh_capture}/haos-activate.sh" || {
    printf 'captured activate script misses the getty mask\n' >&2
    exit 1
}
grep -q 'refusing to drop console=tty0' "${ssh_capture}/haos-activate.sh" || {
    printf 'captured activate script can drop console=tty0\n' >&2
    exit 1
}
grep -q 'systemd-run --unit=haos-dot-files.service' "${ssh_capture}/haos-activate.sh" || {
    printf 'captured activate script does not start the supervisor\n' >&2
    exit 1
}
if grep -q 'systemctl start getty' "${ssh_capture}/haos-activate.sh"; then
    printf 'captured activate script starts a getty\n' >&2
    exit 1
fi
grep -q 'RUN+="/mnt/overlay/dot-files/haos-udev.sh"' "${ssh_capture}/90-haos-dot-files.rules" || {
    printf 'captured udev rule:\n%s\n' "$(cat "${ssh_capture}/90-haos-dot-files.rules")" >&2
    exit 1
}
grep -q 'console is locked' "${ssh_capture}/haos-console-lock.sh" || {
    printf 'captured lock script has no banner\n' >&2
    exit 1
}
grep -q 'HAOS_CONSOLE_DEVICE' "${ssh_capture}/haos-console-lock.sh" || {
    printf 'captured lock script always opens a tty\n' >&2
    exit 1
}

: >"$ssh_log"
rm -rf "$payload"
SSH_MODE=remote
set +e
remote_out="$(run_haos 2>&1)"
remote_rc=$?
set -e
[[ "$remote_rc" -ne 0 ]] || {
    printf 'remote command failure should stop:\n%s\n' "$remote_out" >&2
    exit 1
}
[[ ! -e "${payload}/authorized_keys" ]] || {
    printf 'remote command failure wrote a CONFIG payload\n' >&2
    exit 1
}
if grep -q 'is not up' <<<"$remote_out"; then
    printf 'remote command failure claimed the port was down:\n%s\n' "$remote_out" >&2
    exit 1
fi
if grep -q 'host options' "$ssh_log"; then
    printf 'remote command failure sent a hostname command\n' >&2
    exit 1
fi
grep -q 'remote command failed' <<<"$remote_out" || {
    printf 'remote command failure hid ssh stderr:\n%s\n' "$remote_out" >&2
    exit 1
}

: >"$ssh_log"
rm -rf "$payload"
SSH_MODE=hostkey
set +e
hostkey_out="$(run_haos 2>&1)"
hostkey_rc=$?
set -e
[[ "$hostkey_rc" -ne 0 ]] || {
    printf 'host key failure should stop:\n%s\n' "$hostkey_out" >&2
    exit 1
}
[[ ! -e "${payload}/authorized_keys" ]] || {
    printf 'host key failure wrote a CONFIG payload\n' >&2
    exit 1
}
if grep -q 'is not up' <<<"$hostkey_out"; then
    printf 'host key failure claimed the port was down:\n%s\n' "$hostkey_out" >&2
    exit 1
fi
grep -q 'REMOTE HOST IDENTIFICATION HAS CHANGED' <<<"$hostkey_out" || {
    printf 'host key failure hid ssh stderr:\n%s\n' "$hostkey_out" >&2
    exit 1
}

: >"$ssh_log"
rm -rf "$payload"
SSH_MODE=installfail
set +e
install_out="$(run_haos 2>&1)"
install_rc=$?
set -e
[[ "$install_rc" -ne 0 ]] || {
    printf 'failed key install should stop:\n%s\n' "$install_out" >&2
    exit 1
}
if grep -q 'installed SSH keys' <<<"$install_out"; then
    printf 'failed key install reported success:\n%s\n' "$install_out" >&2
    exit 1
fi
if grep -q 'host options' "$ssh_log"; then
    printf 'failed key install sent a hostname command\n' >&2
    exit 1
fi
grep -q 'failed to install authorized_keys' <<<"$install_out" || {
    printf 'failed key install missing error:\n%s\n' "$install_out" >&2
    exit 1
}

: >"$ssh_log"
rm -rf "$payload"
SSH_MODE=denied
set +e
denied_out="$(run_haos 2>&1)"
denied_rc=$?
set -e
[[ "$denied_rc" -ne 0 ]] || {
    printf 'refused key login should stop:\n%s\n' "$denied_out" >&2
    exit 1
}
[[ ! -e "${payload}/authorized_keys" ]] || {
    printf 'refused key login wrote a CONFIG payload\n' >&2
    exit 1
}
if grep -q 'is not up' <<<"$denied_out"; then
    printf 'refused key login claimed the port was down:\n%s\n' "$denied_out" >&2
    exit 1
fi
if grep -q 'host options' "$ssh_log"; then
    printf 'refused key login sent a hostname command\n' >&2
    exit 1
fi
grep -q 'was refused' <<<"$denied_out" || {
    printf 'refused key login missing error:\n%s\n' "$denied_out" >&2
    exit 1
}
grep -q 'Permission denied' <<<"$denied_out" || {
    printf 'refused key login hid ssh stderr:\n%s\n' "$denied_out" >&2
    exit 1
}

: >"$ssh_log"
rm -rf "$payload" "$ssh_capture"
SSH_MODE=syncfail
set +e
syncfail_out="$(run_haos 2>&1)"
syncfail_rc=$?
set -e
[[ "$syncfail_rc" -ne 0 ]] || {
    printf 'updater install failure should stop:\n%s\n' "$syncfail_out" >&2
    exit 1
}
grep -q 'failed to install /mnt/overlay/dot-files/sync-github-keys.sh' <<<"$syncfail_out" || {
    printf 'updater install failure missing error:\n%s\n' "$syncfail_out" >&2
    exit 1
}
if grep -q 'host options' "$ssh_log"; then
    printf 'updater install failure sent a hostname command\n' >&2
    exit 1
fi
if grep -q 'ha-cli@tty1' "$ssh_log"; then
    printf 'updater install failure locked the console\n' >&2
    exit 1
fi
[[ ! -e "${payload}/authorized_keys" ]] || {
    printf 'updater install failure wrote a CONFIG payload\n' >&2
    exit 1
}

: >"$ssh_log"
rm -rf "$payload" "$ssh_capture"
SSH_MODE=syncwarn
set +e
syncwarn_out="$(run_haos 2>&1)"
syncwarn_rc=$?
set -e
[[ "$syncwarn_rc" -eq 0 ]] || {
    printf 'a failed key refresh should still finish:\n%s\n' "$syncwarn_out" >&2
    exit 1
}
grep -q 'supervisor will retry' <<<"$syncwarn_out" || {
    printf 'failed key refresh missing the retry warning:\n%s\n' "$syncwarn_out" >&2
    exit 1
}
grep -q 'ha host options --hostname ward-drake' "$ssh_log" || {
    printf 'failed key refresh skipped the hostname:\n%s\n' "$(cat "$ssh_log")" >&2
    exit 1
}
grep -q 'locked the console' <<<"$syncwarn_out" || {
    printf 'failed key refresh skipped the console lock:\n%s\n' "$syncwarn_out" >&2
    exit 1
}

: >"$ssh_log"
rm -rf "$payload" "$ssh_capture"
SSH_MODE=lockfail
set +e
lockfail_out="$(run_haos 2>&1)"
lockfail_rc=$?
set -e
[[ "$lockfail_rc" -ne 0 ]] || {
    printf 'console lock failure should stop:\n%s\n' "$lockfail_out" >&2
    exit 1
}
grep -q 'failed to lock the console' <<<"$lockfail_out" || {
    printf 'console lock failure missing error:\n%s\n' "$lockfail_out" >&2
    exit 1
}
grep -q 'Failed to mask ha-cli@tty1.service' <<<"$lockfail_out" || {
    printf 'console lock failure hid ssh stderr:\n%s\n' "$lockfail_out" >&2
    exit 1
}
grep -q 'ha host options --hostname ward-drake' "$ssh_log" || {
    printf 'console lock failure skipped the hostname\n' >&2
    exit 1
}
if grep -q 'locked the console' <<<"$lockfail_out"; then
    printf 'console lock failure reported success:\n%s\n' "$lockfail_out" >&2
    exit 1
fi

sync_sh="${repo}/setup/files/ssh/haos-sync-github-keys.sh"
lock_sh="${repo}/setup/files/ssh/haos-console-lock.sh"
home_sync="${work}/sync-home"
mkdir -p "${home_sync}/.ssh"
printf 'OLD\n' >"${home_sync}/.ssh/authorized_keys"
chmod 0600 "${home_sync}/.ssh/authorized_keys"

run_sync() {
    env PATH="${bin}:${old_path}" \
        GITHUB_KEYS_USER=DragonCrafted87 \
        DOTFILES_HOME="$home_sync" \
        CURL_MODE="$1" \
        /bin/sh "$sync_sh"
}

set +e
sync_fetch_out="$(run_sync fail 2>&1)"
sync_fetch_rc=$?
set -e
[[ "$sync_fetch_rc" -ne 0 ]] || {
    printf 'updater fetch failure should stop:\n%s\n' "$sync_fetch_out" >&2
    exit 1
}
[[ "$(cat "${home_sync}/.ssh/authorized_keys")" == "OLD" ]] || {
    printf 'updater fetch failure replaced authorized_keys\n' >&2
    exit 1
}

set +e
sync_bad_out="$(run_sync bad 2>&1)"
sync_bad_rc=$?
set -e
[[ "$sync_bad_rc" -ne 0 ]]
[[ "$(cat "${home_sync}/.ssh/authorized_keys")" == "OLD" ]] || {
    printf 'updater non-key body replaced authorized_keys:\n%s\n' "$sync_bad_out" >&2
    exit 1
}

set +e
sync_empty_out="$(run_sync empty 2>&1)"
sync_empty_rc=$?
set -e
[[ "$sync_empty_rc" -ne 0 ]]
[[ "$(cat "${home_sync}/.ssh/authorized_keys")" == "OLD" ]] || {
    printf 'updater empty body replaced authorized_keys:\n%s\n' "$sync_empty_out" >&2
    exit 1
}

sync_ok_out="$(run_sync ok 2>&1)"
grep -q "$expect_keys" "${home_sync}/.ssh/authorized_keys" || {
    printf 'updater did not write the key:\n%s\n' "$(cat "${home_sync}/.ssh/authorized_keys")" >&2
    exit 1
}
grep -q '^# synced from https://github.com/DragonCrafted87.keys at ' \
    "${home_sync}/.ssh/authorized_keys" || {
    printf 'updater missing the sync comment:\n%s\n' "$sync_ok_out" >&2
    exit 1
}
[[ "$(stat -c %a "${home_sync}/.ssh/authorized_keys")" == "600" ]] || {
    printf 'updater mode is %s\n' "$(stat -c %a "${home_sync}/.ssh/authorized_keys")" >&2
    exit 1
}

lock_out="$(printf '\n' | timeout 1 /bin/sh "$lock_sh" 2>/dev/null || true)"
grep -q 'console is locked' <<<"$lock_out" || {
    printf 'lock banner missing:\n%s\n' "$lock_out" >&2
    exit 1
}
grep -q 'port 22222' <<<"$lock_out" || {
    printf 'lock banner missing the SSH port:\n%s\n' "$lock_out" >&2
    exit 1
}
if grep -q $'\033' <<<"$lock_out"; then
    printf 'lock banner cleared a tty when HAOS_CONSOLE_DEVICE was unset\n' >&2
    exit 1
fi
fake_tty="${work}/fake-tty"
: >"$fake_tty"
fake_out="$(HAOS_CONSOLE_DEVICE="$fake_tty" timeout 1 /bin/sh "$lock_sh" 2>/dev/null || true)"
[[ -z "$fake_out" ]] || {
    printf 'lock wrote stdout when a device was set:\n%s\n' "$fake_out" >&2
    exit 1
}
grep -q 'console is locked' "$fake_tty" || {
    printf 'lock banner missing from the device:\n%s\n' "$(cat "$fake_tty")" >&2
    exit 1
}
grep -q $'\033' "$fake_tty" || {
    printf 'lock did not clear the device\n' >&2
    exit 1
}

activate_sh="${repo}/setup/files/ssh/haos-activate.sh"
expect_masks='console=tty0 systemd.mask=ha-cli@tty1.service systemd.mask=getty@tty1.service'
rewritten="$(/bin/sh "$activate_sh" --rewrite-cmdline 'console=tty0')"
[[ "$rewritten" == "$expect_masks" ]] || {
    printf 'cmdline rewrite of console=tty0: %s\n' "$rewritten" >&2
    exit 1
}
again="$(/bin/sh "$activate_sh" --rewrite-cmdline "$rewritten")"
[[ "$again" == "$expect_masks" ]] || {
    printf 'cmdline rewrite was not idempotent: %s\n' "$again" >&2
    exit 1
}
kept="$(/bin/sh "$activate_sh" --rewrite-cmdline 'console=tty0 foo=1 systemd.mask=ha-cli@tty1.service')"
[[ "$kept" == "console=tty0 foo=1 systemd.mask=ha-cli@tty1.service systemd.mask=getty@tty1.service" ]] || {
    printf 'cmdline rewrite dropped a token: %s\n' "$kept" >&2
    exit 1
}
cr="$(/bin/sh "$activate_sh" --rewrite-cmdline $'console=tty0\r')"
[[ "$cr" == "$expect_masks" ]] || {
    printf 'cmdline rewrite kept a CR: %s\n' "$cr" >&2
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
grep -q -- '-p 22222 ' <<<"$dry_out" || {
    printf 'dry-run missing port 22222:\n%s\n' "$dry_out" >&2
    exit 1
}
grep -q 'ha host options --hostname ward-drake' <<<"$dry_out" || {
    printf 'dry-run missing hostname command:\n%s\n' "$dry_out" >&2
    exit 1
}
grep -q '/mnt/overlay/dot-files/haos-activate.sh' <<<"$dry_out" || {
    printf 'dry-run missing the activator:\n%s\n' "$dry_out" >&2
    exit 1
}
grep -q 'ForwardX11=no' <<<"$dry_out" || {
    printf 'dry-run forwarded X11:\n%s\n' "$dry_out" >&2
    exit 1
}
if grep -q 'sync-github-keys.timer\|systemctl start getty\|/root/bin' <<<"$dry_out"; then
    printf 'dry-run used a read-only path or a getty:\n%s\n' "$dry_out" >&2
    exit 1
fi
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
