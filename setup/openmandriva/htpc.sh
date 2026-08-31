#!/usr/bin/env bash
# Home theater PC.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_user
ensure_hostname "${DOTFILES_HOSTNAME:-}"
record_role htpc

run_module configure-ssh-key
run_module register-github-ssh-key
run_module link-dotfiles
run_module link-home-files
run_module harden-secrets
run_module configure-sudoers
run_module link-root-shell
run_module install-oh-my-posh
run_module set-timezone
run_module enable-rock-repos
run_module install-base-packages
run_module configure-boot-display
run_module remove-plasma-sddm
run_module install-hyprland-session
run_module configure-bluetooth-login
run_module install-desktop-packages
run_module install-brave
run_module configure-brave-keyring
run_module enable-session-units
run_module install-k3s
run_module install-boinc
run_module link-user-config
run_module configure-htpc
