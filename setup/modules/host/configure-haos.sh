#!/usr/bin/env bash
# Apply the flight's SSH keys and short hostname on a Home Assistant OS
# appliance. HAOS_TARGET is user@host. HAOS_HOSTNAME defaults to
# ward-drake. When debug SSH on port 22222 is not up yet, write
# authorized_keys for a CONFIG usb and stop. The next run installs the
# keys and sets the hostname.

set -euo pipefail
# shellcheck disable=SC1091
. "${REPO_ROOT:-$DOTFILES_ROOT}/setup/lib/lib.sh"

require_user

target="${HAOS_TARGET:-}"
hostname="${HAOS_HOSTNAME:-ward-drake}"
port="${HAOS_SSH_PORT:-22222}"
config_dir="${HAOS_CONFIG_DIR:-${HOME}/.cache/dot-files/haos-config}"
key_url="https://github.com/${GITHUB_KEYS_USER:-DragonCrafted87}.keys"
key_re='^[A-Za-z0-9._+-]+(@openssh\.com)? [A-Za-z0-9+/=]+'

[[ -n "$target" ]] || die "HAOS_TARGET is required (user@host)"
[[ "$target" != *[[:space:]]* && "$target" == *@?* ]] || die "HAOS_TARGET must be user@host, got ${target}"
[[ "$port" =~ ^[0-9]+$ ]] || die "bad HAOS_SSH_PORT ${port}"
[[ "$hostname" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] || die "bad hostname ${hostname}"

ssh_cmd() {
    ssh -p "$port" \
        -o BatchMode=yes \
        -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=accept-new \
        "$target" \
        "$@"
}

if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
    run ssh -p "$port" -o BatchMode=yes -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=accept-new \
        "$target" ha host info
    run ssh -p "$port" -o BatchMode=yes -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=accept-new \
        "$target" ha host options --hostname "$hostname"
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
trap 'rm -f "$keys_file"' EXIT
fetch_keys >"$keys_file"

probe_file="$(mktemp)"
probe_err="$(mktemp)"
if ssh_cmd \
    'if command -v ha >/dev/null 2>&1; then printf "%s\n" HAOS; ha host info; else printf "%s\n" NOT-HAOS; fi' \
    >"$probe_file" 2>"$probe_err"; then
    kind="$(head -n 1 "$probe_file" | tr -d '\r')"
    rm -f "$probe_file" "$probe_err"
    [[ "$kind" == HAOS ]] || die "refusing ${target}: not Home Assistant OS"
else
    rm -f "$probe_file" "$probe_err"
    payload="$(write_payload <"$keys_file")"
    log "SSH to ${target} port ${port} is not up"
    log "wrote ${payload}"
    log "copy that file onto a USB partition named CONFIG, import it (ha os import, or reboot with the stick attached), then run this command again"
    exit 2
fi

ssh_cmd \
    'mkdir -p /root/.ssh; chmod 700 /root/.ssh; cat > /root/.ssh/authorized_keys; chmod 600 /root/.ssh/authorized_keys; systemctl start dropbear >/dev/null 2>&1 || true' \
    <"$keys_file"
log "installed SSH keys on ${target}"

ssh_cmd ha host options --hostname "$hostname"
log "hostname ${hostname} on ${target}"
