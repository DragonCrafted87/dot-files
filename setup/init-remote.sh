#!/usr/bin/env bash
# Run from a working computer. Opens one SSH master, copies secrets,
# generates a key on the new box, registers that key with the local gh
# session, clones the repo, then runs the role.
#
#   ./setup/init-remote.sh dragon@newbox.lan laptop

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
list="${here}/files/secrets.list"
target="${1:-}"
role="${2:-}"
repo_url="${DOTFILES_REPO_URL:-git@github.com:DragonCrafted87/dot-files.git}"

if [[ -z "$target" || -z "$role" ]]; then
    printf 'usage: %s user@host workstation|laptop|htpc|server\n' "$0" >&2
    exit 1
fi

case "$role" in
    workstation | laptop | htpc | server) ;;
    *)
        printf 'error: unknown role %s\n' "$role" >&2
        exit 1
        ;;
esac

if ! command -v gh >/dev/null 2>&1; then
    printf 'error: gh must be installed and logged in on this computer\n' >&2
    exit 1
fi
if ! gh auth status --hostname github.com >/dev/null 2>&1; then
    printf 'error: run gh auth login on this computer first\n' >&2
    exit 1
fi

ctl_dir="$(mktemp -d "${TMPDIR:-/tmp}/omv-init-ssh.XXXXXX")"
sock="${ctl_dir}/sock"
cleanup() {
    ssh -o ControlPath="$sock" -O exit "$target" >/dev/null 2>&1 || true
    rm -rf "$ctl_dir"
}
trap cleanup EXIT

remote() {
    local tty=()
    if [[ "${1:-}" == "-t" ]]; then
        tty=(-t)
        shift
    fi
    ssh "${tty[@]}" \
        -o ControlMaster=auto \
        -o ControlPath="$sock" \
        -o ControlPersist=10m \
        -o ForwardX11=no \
        -o ForwardX11Trusted=no \
        -o PreferredAuthentications=password,keyboard-interactive,publickey \
        "$target" "$@"
}

printf '==> open ssh master to %s (one password prompt)\n' "$target"
ssh -fN \
    -o ControlMaster=yes \
    -o ControlPath="$sock" \
    -o ControlPersist=10m \
    -o ForwardX11=no \
    -o ForwardX11Trusted=no \
    "$target"
ssh -o ControlPath="$sock" -O check "$target"

printf '==> install SSH public keys on %s\n' "$target"
remote 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
install_remote_key() {
    local key="$1"
    key="$(printf '%s' "$key" | tr -d '\r')"
    [[ -z "$key" || "$key" == \#* ]] && return 0
    remote "grep -Fqx $(printf '%q' "$key") ~/.ssh/authorized_keys || printf '%s\n' $(printf '%q' "$key") >> ~/.ssh/authorized_keys"
}
if [[ -f "${HOME}/.ssh/id_ed25519.pub" ]]; then
    install_remote_key "$(cat "${HOME}/.ssh/id_ed25519.pub")"
fi
if [[ -f "${HOME}/.ssh/authorized_keys" ]]; then
    while IFS= read -r line || [[ -n "${line:-}" ]]; do
        install_remote_key "$line"
    done <"${HOME}/.ssh/authorized_keys"
fi
repo_keys="${here}/files/ssh/authorized_keys"
if [[ -f "$repo_keys" ]]; then
    while IFS= read -r line || [[ -n "${line:-}" ]]; do
        install_remote_key "$line"
    done <"$repo_keys"
fi

printf '==> copy secrets\n'
copied=0
skipped=0
if [[ -f "$list" ]]; then
    while IFS= read -r rel || [[ -n "${rel:-}" ]]; do
        [[ -z "$rel" || "$rel" == \#* ]] && continue
        src="${HOME}/${rel}"
        if [[ ! -e "$src" ]]; then
            printf 'skip (missing): %s\n' "$src"
            skipped=$((skipped + 1))
            continue
        fi
        remote_dir="$(dirname "$rel")"
        if [[ "$remote_dir" != "." ]]; then
            remote "mkdir -p -- ${remote_dir}"
        fi
        printf 'copy %s -> %s:%s\n' "$src" "$target" "$rel"
        remote "cat > $(printf '%q' "$rel")" <"$src"
        copied=$((copied + 1))
    done <"$list"
fi
printf '==> copied %s, skipped %s\n' "$copied" "$skipped"

printf '==> bootstrap git on %s\n' "$target"
remote -t 'sudo dnf install -y git curl'
remote 'mkdir -p ~/.ssh && chmod 700 ~/.ssh'
remote 'if [[ ! -f ~/.ssh/id_ed25519 ]]; then ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "$(id -un)@$(hostname -s)" -N ""; chmod 600 ~/.ssh/id_ed25519; chmod 644 ~/.ssh/id_ed25519.pub; fi'

pubkey="$(remote 'cat ~/.ssh/id_ed25519.pub')"
printf '==> public key:\n%s\n' "$pubkey"
printf '%s\n' "$pubkey" >"${ctl_dir}/newhost.pub"

if gh ssh-key list 2>/dev/null | grep -Fq "$(awk '{print $2}' "${ctl_dir}/newhost.pub")"; then
    printf '==> key already on GitHub\n'
else
    title="$(remote 'hostname -s')-$(date +%F)"
    printf '==> gh ssh-key add on this computer as %s\n' "$title"
    gh ssh-key add "${ctl_dir}/newhost.pub" --title "$title"
fi

printf '==> clone %s\n' "$repo_url"
remote "if [[ ! -d ~/dot-files/.git ]]; then git clone $(printf '%q' "$repo_url") ~/dot-files; fi"
