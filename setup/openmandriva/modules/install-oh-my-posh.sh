#!/usr/bin/env bash
# Install or update Oh My Posh into ~/bin using the repo's installer.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user
ensure_dir "${OMP_INSTALL_DIR}"

installer="${DOTFILES_DIR}/scripts/install-omp.sh"
[[ -f "$installer" ]] || die "missing ${installer}"

if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
    printf 'dry-run: bash %s -d %s\n' "$installer" "${OMP_INSTALL_DIR}"
    exit 0
fi

bash "$installer" -d "${OMP_INSTALL_DIR}"
