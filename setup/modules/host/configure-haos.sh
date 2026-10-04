#!/usr/bin/env bash
# Install the flight's SSH keys on the Home Assistant OS host, refresh
# them from GitHub, set its short hostname, and lock the HDMI console.
# HAOS_TARGET is user@host. Host SSH listens on HAOS_SSH_PORT (default
# 22222). Key login writes /root/.ssh/authorized_keys. A closed port
# writes authorized_keys for a CONFIG usb and stops. This does not use
# the Terminal & SSH app. /usr is read-only and the host shell is ash,
# so the updater lives in /root and /etc. The console lock masks
# ha-cli@tty1 and getty@tty1 and holds tty1. It does not open a getty.

set -euo pipefail
# shellcheck disable=SC1091
. "${REPO_ROOT:-$DOTFILES_ROOT}/setup/lib/lib.sh"

require_user

target="${HAOS_TARGET:-}"
hostname="${HAOS_HOSTNAME:-ward-drake}"
port="${HAOS_SSH_PORT:-22222}"
config_dir="${HAOS_CONFIG_DIR:-${HOME}/.cache/dot-files/haos-config}"
keys_user="${GITHUB_KEYS_USER:-DragonCrafted87}"
haos_ssh_src="${SETUP_FILES_DIR}/ssh"
key_url="https://github.com/${keys_user}.keys"
key_re='^[A-Za-z0-9._+-]+(@openssh\.com)? [A-Za-z0-9+/=]+'
install_remote='mkdir -p /root/.ssh && chmod 700 /root/.ssh && cat > /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys'
probe_remote='if command -v ha >/dev/null 2>&1; then printf "%s\n" HAOS; else printf "%s\n" NOT-HAOS; fi'

[[ -n "$target" ]] || die "HAOS_TARGET is required (user@host)"
[[ "$target" != *[[:space:]]* && "$target" == *@?* ]] || die "HAOS_TARGET must be user@host, got ${target}"
[[ "$port" =~ ^[0-9]+$ ]] || die "bad HAOS_SSH_PORT ${port}"
[[ "$hostname" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] || die "bad hostname ${hostname}"
[[ "$keys_user" =~ ^[A-Za-z0-9-]+$ ]] || die "bad GITHUB_KEYS_USER ${keys_user}"

ssh_common=(
    -p "$port"
    -o ConnectTimeout=10
    -o StrictHostKeyChecking=accept-new
)

ssh_keys() {
    ssh "${ssh_common[@]}" \
        -o BatchMode=yes \
        -o PreferredAuthentications=publickey \
        "$target" \
        "$@"
}

# ssh uses exit 255 for its own failures. A remote command keeps its status.
classify_ssh() {
    local status="$1" errfile="$2"
    if [[ "$status" -ne 255 ]]; then
        printf 'remote\n'
        return 0
    fi
    if grep -qiE 'permission denied|authentication failed' "$errfile"; then
        printf 'auth\n'
        return 0
    fi
    if grep -qiE 'connection refused|timed out|no route to host|could not resolve|network is unreachable|connection reset' "$errfile"; then
        printf 'down\n'
        return 0
    fi
    printf 'other\n'
}

if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
    run ssh "${ssh_common[@]}" \
        -o BatchMode=yes \
        -o PreferredAuthentications=publickey \
        "$target" \
        ha host options --hostname "$hostname"
    run ssh "${ssh_common[@]}" \
        -o BatchMode=yes \
        -o PreferredAuthentications=publickey \
        "$target" \
        systemctl enable --now sync-github-keys.timer
    run ssh "${ssh_common[@]}" \
        -o BatchMode=yes \
        -o PreferredAuthentications=publickey \
        "$target" \
        "systemctl mask --now ha-cli@tty1.service && systemctl mask getty@tty1.service && systemctl enable haos-console-lock.service && systemctl restart haos-console-lock.service"
    exit 0
fi

fetch_keys() {
    local tmp
    tmp="$(mktemp)"
    if ! curl -fsSL --max-time 20 "$key_url" -o "$tmp"; then
        rm -f "$tmp"
        die "failed to fetch ${key_url}"
    fi
    if ! grep -qE "$key_re" "$tmp"; then
        rm -f "$tmp"
        die "${key_url} did not contain any SSH public keys"
    fi
    grep -E "$key_re" "$tmp"
    rm -f "$tmp"
}

write_payload() {
    local dest="${config_dir}/authorized_keys"
    local tmp
    mkdir -p "$config_dir"
    tmp="$(mktemp "${config_dir}/.authorized_keys.XXXXXX")"
    cat >"$tmp"
    if [[ ! -s "$tmp" ]]; then
        rm -f "$tmp"
        die "refusing to write an empty authorized_keys"
    fi
    chmod 0644 "$tmp"
    mv "$tmp" "$dest"
    printf '%s\n' "$dest"
}

keys_file="$(mktemp)"
service_tmp=""
trap 'rm -f "$keys_file"; if [[ -n "${service_tmp}" ]]; then rm -f "$service_tmp"; fi' EXIT
fetch_keys >"$keys_file"

push_remote() {
    local mode="$1"
    local dest="$2"
    local src="$3"
    local dir="${dest%/*}"
    ssh_keys "mkdir -p ${dir} && cat > ${dest} && chmod ${mode} ${dest}" <"$src"
}

while true; do
    probe_file="$(mktemp)"
    probe_err="$(mktemp)"
    set +e
    ssh_keys "$probe_remote" >"$probe_file" 2>"$probe_err"
    probe_rc=$?
    set -e
    if [[ "$probe_rc" -eq 0 ]]; then
        kind="$(head -n 1 "$probe_file" | tr -d '\r')"
        rm -f "$probe_file" "$probe_err"
        [[ "$kind" == HAOS ]] || die "refusing ${target}: not Home Assistant OS"
        break
    fi
    class="$(classify_ssh "$probe_rc" "$probe_err")"
    case "$class" in
        down)
            payload="$(write_payload <"$keys_file")"
            log "SSH to ${target} port ${port} is not up"
            if [[ -s "$probe_err" ]]; then
                cat "$probe_err" >&2
            fi
            rm -f "$probe_file" "$probe_err"
            log "wrote ${payload}"
            log "copy that file onto a USB partition named CONFIG, import it (ha os import, or reboot with the stick attached), then run this command again"
            exit 2
            ;;
        auth)
            if [[ -s "$probe_err" ]]; then
                cat "$probe_err" >&2
            fi
            rm -f "$probe_file" "$probe_err"
            die "key login to ${target} port ${port} was refused"
            ;;
        *)
            if [[ -s "$probe_err" ]]; then
                cat "$probe_err" >&2
            fi
            if [[ -s "$probe_file" ]]; then
                cat "$probe_file" >&2
            fi
            rm -f "$probe_file" "$probe_err"
            die "SSH to ${target} port ${port} failed"
            ;;
    esac
done

if ! ssh_keys "$install_remote" <"$keys_file"; then
    die "failed to install authorized_keys on ${target}"
fi
# Host SSH is dropbear. A missing unit stays a success when this session is already up.
ssh_keys 'systemctl start dropbear >/dev/null 2>&1 || true' || true
log "installed SSH keys on ${target}"

sync_bin="/root/bin/sync-github-keys.sh"
lock_bin="/root/bin/haos-console-lock.sh"
if ! push_remote 0755 "$sync_bin" "${haos_ssh_src}/haos-sync-github-keys.sh"; then
    die "failed to install ${sync_bin} on ${target}"
fi
service_tmp="$(mktemp)"
sed "s/^Environment=GITHUB_KEYS_USER=.*/Environment=GITHUB_KEYS_USER=${keys_user}/" \
    "${haos_ssh_src}/haos-sync-github-keys.service" >"$service_tmp"
if ! push_remote 0644 /etc/systemd/system/sync-github-keys.service "$service_tmp"; then
    die "failed to install sync-github-keys.service on ${target}"
fi
if ! push_remote 0644 /etc/systemd/system/sync-github-keys.timer \
    "${haos_ssh_src}/haos-sync-github-keys.timer"; then
    die "failed to install sync-github-keys.timer on ${target}"
fi
if ! push_remote 0755 "$lock_bin" "${haos_ssh_src}/haos-console-lock.sh"; then
    die "failed to install ${lock_bin} on ${target}"
fi
if ! push_remote 0644 /etc/systemd/system/haos-console-lock.service \
    "${haos_ssh_src}/haos-console-lock.service"; then
    die "failed to install haos-console-lock.service on ${target}"
fi
if ! ssh_keys 'systemctl daemon-reload && systemctl enable --now sync-github-keys.timer'; then
    die "failed to enable sync-github-keys.timer on ${target}"
fi
log "enabled GitHub key timer on ${target}"
if ! ssh_keys "GITHUB_KEYS_USER=${keys_user} DOTFILES_HOME=/root ${sync_bin}"; then
    warn "GitHub key sync failed this run; timer will retry"
fi

if ! ssh_keys ha host options --hostname "$hostname"; then
    die "failed to set hostname ${hostname} on ${target}"
fi
log "hostname ${hostname} on ${target}"

lock_remote='systemctl mask --now ha-cli@tty1.service && systemctl mask getty@tty1.service && systemctl enable haos-console-lock.service && systemctl restart haos-console-lock.service'
if ! ssh_keys "$lock_remote"; then
    die "failed to lock the console on ${target}"
fi
log "locked the console on ${target}"
