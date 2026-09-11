#!/usr/bin/env bash
# BOINC via Flathub on every role. Manager is the same Flatpak.
# Data lives in ~/.var/app/edu.berkeley.BOINC so a user systemd unit
# can run the client after logout (linger).

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

ensure_packages flatpak
ensure_flatpak_remote flathub https://flathub.org/repo/flathub.flatpakrepo
ensure_flatpak edu.berkeley.BOINC

# Drop the Fedora RPMs if a previous role run installed them.
if [[ -f /etc/yum.repos.d/boinc-stable.repo ]]; then
    log "remove leftover BOINC distro repo"
    run sudo rm -f /etc/yum.repos.d/boinc-stable.repo
fi
if systemctl list-unit-files boinc-client.service >/dev/null 2>&1; then
    disable_service boinc-client.service || true
fi
remove_packages boinc-client boinc-manager || true

boinc_dir="${DOTFILES_HOME}/.var/app/edu.berkeley.BOINC"
rpc_file="${boinc_dir}/gui_rpc_auth.cfg"
secret="${DOTFILES_HOME}/.config/dot-files/boinc-rpc.password"
src="${SETUP_FILES_DIR}/boinc"
role="${OMV_ROLE:-}"
if [[ -z "$role" && -f "${CONFIG_TARGET_DIR}/dot-files/role" ]]; then
    role="$(tr -d '[:space:]' <"${CONFIG_TARGET_DIR}/dot-files/role")"
fi
role="${role:-server}"
prefs_src="${src}/prefs/${role}.xml"
[[ -f "$prefs_src" ]] || die "missing role prefs ${prefs_src}"

if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
    log "configure ${boinc_dir} from ${src} (prefs ${role})"
    exit 0
fi

ensure_dir "$boinc_dir"
ensure_dir "${DOTFILES_HOME}/.config/systemd/user"
ensure_dir /etc/boinc-client || run sudo mkdir -p /etc/boinc-client

install -m 0644 "${src}/boinc-client.service" \
    "${DOTFILES_HOME}/.config/systemd/user/boinc-client.service"

write_wrapper() {
    local dest="$1"
    local command="$2"
    local tmp
    tmp="$(mktemp)"
    cat >"$tmp" <<EOF
#!/usr/bin/env bash
exec /usr/bin/flatpak run --command=${command} edu.berkeley.BOINC "\$@"
EOF
    sudo install -m 0755 "$tmp" "$dest"
    rm -f "$tmp"
}
write_wrapper /usr/local/bin/boinccmd boinccmd
write_wrapper /usr/local/bin/boincmgr boincmgr

boinc_changed=0
install_boinc_file() {
    local from="$1"
    local to="$2"
    local mode="${3:-0644}"
    local as_root="${4:-0}"
    if [[ -f "$to" ]] && cmp -s "$from" "$to"; then
        return 0
    fi
    log "update ${to}"
    if [[ "$as_root" == "1" ]]; then
        sudo install -m "$mode" "$from" "$to"
    else
        install -m "$mode" "$from" "$to"
    fi
    boinc_changed=1
}

ensure_dir "${DOTFILES_HOME}/.config/dot-files"
rpc_password=""
science_united_user=""
science_united_password=""
if [[ -f "$secret" ]]; then
    if grep -q '=' "$secret"; then
        while IFS='=' read -r key value || [[ -n "${key:-}" ]]; do
            [[ -z "$key" || "$key" == \#* ]] && continue
            key="${key%"${key##*[![:space:]]}"}"
            value="${value%"${value##*[![:space:]]}"}"
            value="${value#"${value%%[![:space:]]*}"}"
            case "$key" in
                rpc_password) rpc_password="$value" ;;
                science_united_user) science_united_user="$value" ;;
                science_united_password) science_united_password="$value" ;;
            esac
        done <"$secret"
    else
        rpc_password="$(tr -d '[:space:]' <"$secret")"
    fi
fi
if [[ -z "$rpc_password" && -f "$rpc_file" ]]; then
    rpc_password="$(tr -d '[:space:]' <"$rpc_file")"
fi
if [[ -z "$rpc_password" ]]; then
    rpc_password="$(head -c 32 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 32)"
    warn "generated rpc_password in ${secret}; copy that file to the other boxes"
fi
umask 077
cat >"$secret" <<EOF
rpc_password=${rpc_password}
science_united_user=${science_united_user}
science_united_password=${science_united_password}
EOF
chmod 600 "$secret"
if [[ -z "$science_united_user" || -z "$science_united_password" ]]; then
    warn "add science_united_user (email) and science_united_password to ${secret}"
fi
current_rpc=""
if [[ -f "$rpc_file" ]]; then
    current_rpc="$(tr -d '[:space:]' <"$rpc_file")"
fi
if [[ "$current_rpc" != "$rpc_password" ]]; then
    printf '%s\n' "$rpc_password" >"$rpc_file"
    chmod 600 "$rpc_file"
    boinc_changed=1
fi

install_boinc_file "${src}/cc_config.xml" "${boinc_dir}/cc_config.xml"
install_boinc_file "$prefs_src" "${boinc_dir}/global_prefs_override.xml"

install_boinc_file "${src}/hosts.list" /etc/boinc-client/hosts.list 0644 1
tmp="$(mktemp)"
grep -vE '^[[:space:]]*(#|$)' "${src}/hosts.list" >"$tmp" || true
if [[ ! -s "$tmp" ]]; then
    warn "files/boinc/hosts.list has no live hosts; remote manager will be denied until you add some"
fi
install_boinc_file "$tmp" "${boinc_dir}/remote_hosts.cfg"
rm -f "$tmp"

install_boinc_file "${src}/find-boinccmd.sh" /usr/local/bin/find-boinccmd.sh 0644 1
install_boinc_file "${src}/boinc-config.sh" /usr/local/bin/boinc-config.sh 0755 1
install_boinc_file "${src}/boinc-status.sh" /usr/local/bin/boinc-status.sh 0755 1
install_boinc_file "${src}/boinc-status-all.sh" /usr/local/bin/boinc-status-all.sh 0755 1

if command -v loginctl >/dev/null 2>&1; then
    if ! loginctl show-user "${DOTFILES_USER}" -p Linger 2>/dev/null | grep -qx 'Linger=yes'; then
        log "enable lingering for ${DOTFILES_USER} so BOINC survives logout"
        run sudo loginctl enable-linger "${DOTFILES_USER}"
    fi
fi

systemctl --user daemon-reload
enable_user_service boinc-client.service
if [[ "$boinc_changed" -eq 1 ]] || ! systemctl --user is-active --quiet boinc-client.service; then
    log "restart boinc-client user unit"
    run systemctl --user restart boinc-client.service || run systemctl --user start boinc-client.service
    sleep 3
fi

if command -v firewall-cmd >/dev/null && systemctl is-active --quiet firewalld; then
    if ! sudo firewall-cmd --query-port=31416/tcp >/dev/null 2>&1; then
        log "firewalld allow 31416/tcp"
        sudo firewall-cmd --permanent --add-port=31416/tcp
        sudo firewall-cmd --reload
    fi
fi

log "prefs ${role} from ${prefs_src}"
if [[ -n "$science_united_user" && -n "$science_united_password" ]]; then
    log "attach Science United"
    BOINC_SECRET="$secret" /usr/local/bin/boinc-config.sh || \
        warn "Science United attach failed; retry with /usr/local/bin/boinc-config.sh"
else
    warn "Science United skipped until ${secret} has the login fields"
fi
log "status: /usr/local/bin/boinc-status.sh"
log "manager: boincmgr   or   flatpak run edu.berkeley.BOINC"
