#!/usr/bin/env bash
# Point Brave at GNOME Keyring / libsecret instead of KWallet, and make
# ly/login PAM unlock the keyring named "login" with the Unix password.
# Existing KWallet-encrypted logins will not migrate; sign in again once.
#
# PAM only auto-unlocks the keyring whose name is exactly "login".
# If Seahorse shows "Default keyring", rename it to login (same password
# as the account) so the next graphical login unlocks it.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

ensure_packages gnome-keyring libsecret

ensure_pam_line() {
    local file="$1"
    local line="$2"
    [[ -f "$file" ]] || return 0
    if grep -Fqx "$line" "$file"; then
        return 0
    fi
    log "pam: ${line} -> ${file}"
    if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
        printf '\n%s\n' "$line" | sudo tee -a "$file" >/dev/null
    fi
}

# ly includes login. Put the auth token capture on both, and start the
# daemon on session. passwd keeps the keyring password in sync later.
for pam_file in /etc/pam.d/ly /etc/pam.d/login /etc/pam.d/system-auth; do
    ensure_pam_line "$pam_file" 'auth       optional     pam_gnome_keyring.so'
    ensure_pam_line "$pam_file" 'session    optional     pam_gnome_keyring.so auto_start'
done
ensure_pam_line /etc/pam.d/passwd 'password   optional     pam_gnome_keyring.so'

keyrings="${DOTFILES_HOME}/.local/share/keyrings"
ensure_dir "$keyrings"
default_ptr="${keyrings}/default"
if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
    if [[ ! -f "$default_ptr" ]] || ! grep -qx 'login' "$default_ptr"; then
        log "default keyring name -> login (${default_ptr})"
        printf 'login\n' >"$default_ptr"
        chmod 600 "$default_ptr" || true
    fi
    if [[ ! -e "${keyrings}/login.keyring" ]]; then
        log "no login.keyring yet; create one named login in Seahorse with the account password"
        if compgen -G "${keyrings}/*.keyring" >/dev/null; then
            log "existing keyrings: $(find "$keyrings" -name '*.keyring' -printf '%f ' 2>/dev/null || true)"
        fi
    fi
fi

flags="${DOTFILES_HOME}/.config/brave-flags.conf"
ensure_dir "$(dirname "$flags")"
want_flags=(
    '--password-store=gnome-libsecret'
    '--restore-last-session'
)
if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
    touch "$flags"
    for flag in "${want_flags[@]}"; do
        if ! grep -Fqx "$flag" "$flags"; then
            log "brave flag ${flag}"
            printf '%s\n' "$flag" >>"$flags"
        fi
    done
fi

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
if [[ -n "$src" && "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
    log "desktop override ${override}"
    sed \
        -e 's|^Exec=\(.*brave[^ ]*\)|Exec=\1 --password-store=gnome-libsecret --restore-last-session|' \
        "$src" >"$override"
fi
