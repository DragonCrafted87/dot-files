remove_flatpak_boinc

if systemctl --user list-unit-files boinc-client.service >/dev/null 2>&1; then
    if systemctl --user is-active --quiet boinc-client.service; then
        log "stop user boinc-client before rebuild"
        run systemctl --user stop boinc-client.service || true
    fi
fi
if systemctl list-unit-files boinc-client.service >/dev/null 2>&1; then
    disable_service boinc-client.service || true
fi

if boinc_already_built; then
    log "BOINC ${BOINC_VERSION} already installed"
else
    build_boinc
fi

migrate_data_dir
remove_stale_path_cmds

rpc_file="${BOINC_DIR}/gui_rpc_auth.cfg"
secret="${DOTFILES_HOME}/.config/dot-files/boinc-rpc.password"
src="${SETUP_FILES_DIR}/boinc"
prefs_dir="${src}/prefs"
role="${OMV_ROLE:-}"
if [[ -z "$role" && -f "${CONFIG_TARGET_DIR}/dot-files/role" ]]; then
    role="$(tr -d '[:space:]' <"${CONFIG_TARGET_DIR}/dot-files/role")"
fi
role="${role:-server}"
prefs_src="${prefs_dir}/${role}.xml"
[[ -f "$prefs_src" ]] || die "missing role prefs ${prefs_src}"

hosts_list="${src}/hosts.list"
short_host="$(hostname -s 2>/dev/null || hostname)"
short_host="${short_host%%.*}"

boinc_role_header() {
    case "$1" in
        workstation) printf '%s\n' '# workstation' ;;
        laptop) printf '%s\n' '# laptop' ;;
        htpc) printf '%s\n' '# htpcs' ;;
        server) printf '%s\n' '# servers' ;;
        *) printf '# %s\n' "$1" ;;
    esac
}

host_in_list() {
    local list="$1" name="$2" line stripped
    [[ -f "$list" ]] || return 1
    while IFS= read -r line || [[ -n "${line:-}" ]]; do
        stripped="${line%%#*}"
        stripped="${stripped//[[:space:]]/}"
        [[ -z "$stripped" ]] && continue
        stripped="${stripped%%.*}"
        if [[ "$stripped" == "$name" ]]; then
            return 0
        fi
    done <"$list"
    return 1
}

ensure_host_in_list() {
    local list="$1" name="$2" header="$3"
    local tmp line inserted=0
    if host_in_list "$list" "$name"; then
        return 0
    fi
    log "add ${name} to hosts.list under ${header}"
    [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]] && return 0
    tmp="$(mktemp)"
    if [[ -f "$list" ]]; then
        while IFS= read -r line || [[ -n "${line:-}" ]]; do
            printf '%s\n' "$line" >>"$tmp"
            if [[ "$line" == "$header" ]]; then
                printf '%s\n' "$name" >>"$tmp"
                inserted=1
            fi
        done <"$list"
    fi
    if [[ "$inserted" -eq 0 ]]; then
        printf '\n%s\n%s\n' "$header" "$name" >>"$tmp"
    fi
    cat "$tmp" >"$list"
    rm -f "$tmp"
}

ensure_host_in_list "$hosts_list" "$short_host" "$(boinc_role_header "$role")"

if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
    log "configure ${BOINC_DIR} from ${src} (prefs ${role})"
    exit 0
fi

ensure_dir "$BOINC_DIR"
ensure_dir "${DOTFILES_HOME}/.config/systemd/user"
ensure_dir /etc/boinc-client || run sudo mkdir -p /etc/boinc-client

install -m 0644 "${src}/boinc-client.service" \
    "${DOTFILES_HOME}/.config/systemd/user/boinc-client.service"

boinc_changed=0
install_boinc_file() {
    local from="$1" to="$2" mode="${3:-0644}" as_root="${4:-0}"
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
    boinc_changed=1
fi
chmod 644 "$rpc_file"
write_config_properties
link_rpc_auth

install_boinc_file "${src}/cc_config.xml" "${BOINC_DIR}/cc_config.xml"
log "link ${BOINC_DIR}/global_prefs_override.xml -> ${prefs_src}"
rm -f "${BOINC_DIR}/global_prefs_override.xml"
ln -sfn "$prefs_src" "${BOINC_DIR}/global_prefs_override.xml"

install_boinc_file "$hosts_list" /etc/boinc-client/hosts.list 0644 1
tmp="$(mktemp)"
grep -vE '^[[:space:]]*(#|$)' "$hosts_list" >"$tmp" || true
[[ -s "$tmp" ]] || warn "files/boinc/hosts.list has no live hosts; remote manager will be denied until you add some"
install_boinc_file "$tmp" "${BOINC_DIR}/remote_hosts.cfg"
rm -f "$tmp"

install_boinc_file "${src}/boinc-config.sh" /usr/local/bin/boinc-config 0755 1
install_boinc_file "${src}/boinc-status.sh" /usr/local/bin/boinc-status 0755 1
install_boinc_file "${src}/boinc-status-all.sh" /usr/local/bin/boinc-status-all 0755 1

write_manager_computers "$hosts_list"
install_manager_desktop

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
log "apply role prefs and attach Science United"
BOINC_SECRET="$secret" BOINC_ROLE="$role" BOINC_DIR="$BOINC_DIR" \
    /usr/local/bin/boinc-config || warn "boinc-config failed; retry with /usr/local/bin/boinc-config"
log "status: boinc-status"
log "manager: GTK_THEME=Adwaita:dark boincmgr"
