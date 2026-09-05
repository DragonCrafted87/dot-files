#!/usr/bin/env bash
# Point Brave at GNOME Keyring / libsecret instead of KWallet.
# Existing KWallet-encrypted logins will not migrate; sign in again once.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

ensure_packages gnome-keyring libsecret

pam_ly="/etc/pam.d/ly"
if [[ -f "$pam_ly" ]] && ! grep -q 'pam_gnome_keyring.so' "$pam_ly"; then
    log "add gnome-keyring lines to ${pam_ly}"
    if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
        sudo tee -a "$pam_ly" >/dev/null <<'EOF'

auth       optional     pam_gnome_keyring.so
session    optional     pam_gnome_keyring.so auto_start
EOF
    fi
fi

flags="${DOTFILES_HOME}/.config/brave-flags.conf"
ensure_dir "$(dirname "$flags")"
if [[ -f "$flags" ]] && grep -q 'password-store=gnome-libsecret' "$flags"; then
    :
else
    log "write ${flags}"
    if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
        printf '%s\n' '--password-store=gnome-libsecret' >>"$flags"
    fi
fi

# Session-local desktop override so launchers pick up the flag even if
# brave-flags.conf is ignored on this build.
apps="${DOTFILES_HOME}/.local/share/applications"
ensure_dir "$apps"
override="${apps}/brave-browser.desktop"
src=""
for candidate in /usr/share/applications/brave-browser.desktop /usr/share/applications/com.brave.Browser.desktop; do
    if [[ -f "$candidate" ]]; then
        src="$candidate"
        break
    fi
done
if [[ -n "$src" ]]; then
    log "desktop override ${override}"
    if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
        sed 's|^Exec=\(.*brave[^ ]*\)|Exec=\1 --password-store=gnome-libsecret|' "$src" >"$override"
    fi
fi
