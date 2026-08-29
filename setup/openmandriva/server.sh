#!/usr/bin/env bash
# Headless server. Config folders still get linked; unused GUI apps are harmless.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_user
ensure_hostname "${DOTFILES_HOSTNAME:-}"
record_role server

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
run_module remove-plasma-sddm
run_module install-k3s
run_module install-boinc
run_module link-user-config
run_module configure-server
