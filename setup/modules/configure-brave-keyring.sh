#!/usr/bin/env bash
# Point Brave at GNOME Keyring / libsecret and unlock the login keyring at ly.
#
# OpenMandriva system-auth uses `auth sufficient pam_unix.so`. With
# `auth include login` that sufficient success skips later auth modules in
# the same stack, so pam_gnome_keyring never stashes the password. ly must
# use `auth substack login` so the gnome-keyring auth line still runs.
# Do not also add gnome-keyring lines to login or system-auth — that burns
# PAM_AUTHTOK and logs "couldn't unlock" after a successful start.
#
# The packaged systemd --user gnome-keyring-daemon unit starts a locked
# daemon before PAM. Mask it for this user. Leave D-Bus activation of
# org.freedesktop.secrets alone; it attaches to the PAM daemon.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

ensure_packages gnome-keyring libsecret seahorse

fix_ly_pam() {
    local pam_ly="/etc/pam.d/ly"
    [[ -f "$pam_ly" ]] || return 0

    log "ensure ${pam_ly} uses auth substack + one gnome-keyring pair"
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        return 0
    fi

    sudo python3 - "$pam_ly" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
lines = text.splitlines()
out = []
seen_auth_gkr = False
seen_session_gkr = False
seen_password_gkr = False

for line in lines:
    stripped = line.strip()
    if stripped.startswith("auth") and stripped.split()[0] in {"auth", "-auth"}:
        tokens = stripped.split()
        # auth include login  ->  auth substack login
        if len(tokens) >= 3 and tokens[0] == "auth" and tokens[1] == "include" and tokens[2] == "login":
            out.append("auth       substack     login")
            continue
        if "pam_gnome_keyring.so" in stripped:
            if seen_auth_gkr:
                continue
            seen_auth_gkr = True
            out.append("-auth      optional     pam_gnome_keyring.so")
            continue
    if stripped.startswith(("session", "-session")) and "pam_gnome_keyring.so" in stripped:
        if seen_session_gkr:
            continue
        seen_session_gkr = True
        out.append("-session   optional     pam_gnome_keyring.so auto_start")
        continue
    if stripped.startswith(("password", "-password")) and "pam_gnome_keyring.so" in stripped:
        if seen_password_gkr:
            continue
        seen_password_gkr = True
        out.append("-password  optional     pam_gnome_keyring.so use_authtok")
        continue
    out.append(line)

has_substack = any(
    ln.split()[:3] == ["auth", "substack", "login"] for ln in out if ln.split()
)
if not has_substack:
    rebuilt = []
    inserted = False
    for ln in out:
        rebuilt.append(ln)
        parts = ln.split()
        if not inserted and parts[:3] == ["auth", "include", "login"]:
            rebuilt[-1] = "auth       substack     login"
            inserted = True
    out = rebuilt

def ensure_after(prefix_tokens, new_line):
    global out
    if any(new_line.split() == ln.split() for ln in out if ln.split()):
        return
    rebuilt = []
    added = False
    for ln in out:
        rebuilt.append(ln)
        parts = ln.split()
        if not added and parts[: len(prefix_tokens)] == prefix_tokens:
            rebuilt.append(new_line)
            added = True
    if not added:
        rebuilt.append(new_line)
    out = rebuilt

ensure_after(["auth", "substack", "login"], "-auth      optional     pam_gnome_keyring.so")
ensure_after(["session", "include", "login"], "-session   optional     pam_gnome_keyring.so auto_start")

body = "\n".join(out) + "\n"
if body != text:
    path.write_text(body)
PY
}

strip_extra_gkr_pam() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    if ! sudo grep -q 'pam_gnome_keyring.so' "$file" 2>/dev/null; then
        return 0
    fi
    log "remove gnome-keyring lines from ${file} (ly owns the stack)"
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        return 0
    fi
    sudo python3 - "$file" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
lines = path.read_text().splitlines()
kept = [ln for ln in lines if "pam_gnome_keyring.so" not in ln]
path.write_text("\n".join(kept) + "\n")
PY
}

fix_ly_pam
strip_extra_gkr_pam /etc/pam.d/login
strip_extra_gkr_pam /etc/pam.d/system-auth

# Distro already has -password optional pam_gnome_keyring.so use_authtok on passwd.
# Do not append a second copy.

mask_user_keyring_units() {
    local unit
    for unit in gnome-keyring-daemon.service gnome-keyring-daemon.socket; do
        if systemctl --user is-enabled "$unit" 2>/dev/null | grep -qx masked; then
            continue
        fi
        log "mask --user ${unit}"
        run systemctl --user mask --now "$unit" || true
    done
}

mask_user_keyring_units

hide_xdg_autostart() {
    local dest="${DOTFILES_HOME}/.config/autostart"
    local name
    ensure_dir "$dest"
    for name in secrets pkcs11 ssh; do
        ensure_file_contents "${dest}/gnome-keyring-${name}.desktop" $'[Desktop Entry]\nHidden=true'
    done
}

hide_xdg_autostart

ensure_dir "${DOTFILES_HOME}/.local/share/keyrings"
ensure_file_contents "${DOTFILES_HOME}/.local/share/keyrings/default" "login"

flags="${DOTFILES_HOME}/.config/brave-flags.conf"
ensure_dir "$(dirname "$flags")"
if [[ -f "$flags" ]] && grep -q 'password-store=gnome-libsecret' "$flags"; then
    :
else
    log "write ${flags}"
    if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
        {
            printf '%s\n' '--password-store=gnome-libsecret'
            printf '%s\n' '--restore-last-session'
        } >>"$flags"
    fi
fi
if [[ -f "$flags" ]] && ! grep -q 'restore-last-session' "$flags"; then
    log "append restore-last-session to ${flags}"
    if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
        printf '%s\n' '--restore-last-session' >>"$flags"
    fi
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
if [[ -n "$src" ]]; then
    log "desktop override ${override}"
    if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
        sed 's|^Exec=\(.*brave[^ ]*\)|Exec=\1 --password-store=gnome-libsecret --restore-last-session|' "$src" >"$override"
    fi
fi
