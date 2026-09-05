#!/usr/bin/env bash
# Install the network mount script and user unit. Credentials and rclone
# config are not in the repo; copy them with transfer-secrets.sh.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

src_script="${SETUP_FILES_DIR}/network/mount-network.sh"
src_unit="${SETUP_FILES_DIR}/network/network-mounts.service"
[[ -f "$src_script" ]] || die "missing ${src_script}"
[[ -f "$src_unit" ]] || die "missing ${src_unit}"

ensure_dir "${DOTFILES_HOME}/bin"
ensure_dir "${DOTFILES_HOME}/.config/systemd/user"

run install -m 0755 "$src_script" "${DOTFILES_HOME}/bin/mount-network.sh"
run install -m 0644 "$src_unit" "${DOTFILES_HOME}/.config/systemd/user/network-mounts.service"

if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
    systemctl --user daemon-reload
fi
enable_user_service network-mounts.service

if [[ ! -f "${DOTFILES_HOME}/.smbcredentials" || ! -f "${DOTFILES_HOME}/.config/rclone/rclone.conf" ]]; then
    warn "smb/rclone secrets are not on this machine yet"
    warn "from the old box: ${SETUP_DIR}/utility/transfer-secrets.sh ${DOTFILES_USER}@$(hostname -s)"
fi
