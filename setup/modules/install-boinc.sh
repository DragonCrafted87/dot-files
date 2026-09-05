#!/usr/bin/env bash
# BOINC client on every role. Manager on workstation and laptop.
# Copies hosts.list, cc_config.xml, helper scripts, and the role-specific
# prefs file from the repo on every run so a git pull + role rerun applies.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

# OpenMandriva has no BOINC packages. Download the official x86_64 RPMs
# and install them with dnf so deps come from Rock, not another distro repo.
if [[ -f /etc/yum.repos.d/boinc-stable.repo ]]; then
    log "remove leftover BOINC distro repo"
    run sudo rm -f /etc/yum.repos.d/boinc-stable.repo
fi

boinc_base="${BOINC_RPM_BASE:-https://boinc.berkeley.edu/dl/linux/stable/fc39}"

curl_boinc() {
    curl --retry 5 --retry-all-errors --retry-delay 3 \
        --connect-timeout 15 --max-time 45 "$@"
}

install_boinc_rpms() {
    local want=("$@")
    local missing=()
    local pkg
    for pkg in "${want[@]}"; do
        if ! rpm -q "$pkg" >/dev/null 2>&1; then
            missing+=("$pkg")
        fi
    done
    if [[ "${#missing[@]}" -eq 0 ]]; then
        log "boinc rpms already installed: ${want[*]}"
        return 0
    fi
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        printf 'dry-run: download %s from %s\n' "${missing[*]}" "$boinc_base"
        return 0
    fi
    local index tmp rpm_file names=()
    tmp="$(mktemp -d)"
    if ! index="$(curl_boinc -fsSL "${boinc_base}/")"; then
        warn "could not reach ${boinc_base}; skip rpm download this run"
        rm -rf "$tmp"
        return 0
    fi
    for pkg in "${missing[@]}"; do
        rpm_file="$(printf '%s\n' "$index" | grep -oE "${pkg}-[0-9][^\"<>]*\\.x86_64\\.rpm" | sort -V | tail -n1)"
        if [[ -z "$rpm_file" ]]; then
            warn "no ${pkg} x86_64 rpm listed at ${boinc_base}"
            continue
        fi
        log "download ${rpm_file}"
        if ! curl_boinc -fsSL -o "${tmp}/${rpm_file}" "${boinc_base}/${rpm_file}"; then
            warn "download failed for ${rpm_file}"
            continue
        fi
        names+=("${tmp}/${rpm_file}")
    done
    if [[ "${#names[@]}" -eq 0 ]]; then
        warn "no BOINC rpms downloaded; configure what is already installed"
        rm -rf "$tmp"
        return 0
    fi
    # Fedora RPMs require capabilities named libatomic and libXScrnSaver.
    # Rock ships the same libraries under different package names.
    ensure_packages lib64atomic1 lib64xscrnsaver1
    log "install ${names[*]##*/}"
    if ! sudo dnf install -y "${names[@]}"; then
        warn "dnf refused Fedora Provides; install RPMs with --nodeps"
        sudo rpm -Uvh --nodeps "${names[@]}" || warn "rpm install failed"
    fi
    rm -rf "$tmp"
}

boinc_rpms=(boinc-client)
case "${OMV_ROLE:-}" in
    workstation | laptop)
        boinc_rpms+=(boinc-manager)
        ;;
esac
install_boinc_rpms "${boinc_rpms[@]}"

if ! command -v boinc_client >/dev/null 2>&1 && ! rpm -q boinc-client >/dev/null 2>&1; then
    warn "boinc-client is not installed; skip service and Science United attach"
    exit 0
fi

boinc_dir="/var/lib/boinc"
if [[ -d /var/lib/boinc-client ]]; then
    boinc_dir="/var/lib/boinc-client"
fi
rpc_file="${boinc_dir}/gui_rpc_auth.cfg"
secret="${DOTFILES_HOME}/.config/dot-files/boinc-rpc.password"
src="${SETUP_FILES_DIR}/boinc"
role="${OMV_ROLE:-server}"
prefs_src="${src}/prefs/${role}.xml"
[[ -f "$prefs_src" ]] || die "missing role prefs ${prefs_src}"

if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
    log "configure ${boinc_dir} from ${src} (prefs ${role})"
    exit 0
fi

sudo mkdir -p "$boinc_dir" /etc/boinc-client /usr/local/bin
if getent passwd boinc >/dev/null; then
    sudo chown boinc:boinc "$boinc_dir"
fi

boinc_changed=0
install_boinc_file() {
    local from="$1"
    local to="$2"
    local mode="${3:-0644}"
    if [[ -f "$to" ]] && cmp -s "$from" "$to"; then
        return 0
    fi
    log "update ${to}"
    sudo install -m "$mode" "$from" "$to"
    if getent passwd boinc >/dev/null && [[ "$to" == "${boinc_dir}/"* ]]; then
        sudo chown boinc:boinc "$to"
    fi
    boinc_changed=1
}

# Shared secret file: rpc_password plus Science United login.
# Keep existing science_united_* fields when rewriting.
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
if [[ -z "$rpc_password" ]] && sudo test -f "$rpc_file"; then
    rpc_password="$(sudo cat "$rpc_file" | tr -d '[:space:]')"
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
    warn "add science_united_user and science_united_password to ${secret}"
fi
current_rpc=""
if sudo test -f "$rpc_file"; then
    current_rpc="$(sudo cat "$rpc_file" | tr -d '[:space:]')"
fi
if [[ "$current_rpc" != "$rpc_password" ]]; then
    printf '%s\n' "$rpc_password" | sudo tee "$rpc_file" >/dev/null
    sudo chmod 640 "$rpc_file"
    if getent passwd boinc >/dev/null; then
        sudo chown boinc:boinc "$rpc_file"
    fi
    boinc_changed=1
fi

install_boinc_file "${src}/cc_config.xml" "${boinc_dir}/cc_config.xml"
install_boinc_file "$prefs_src" "${boinc_dir}/global_prefs_override.xml"

# hosts.list from the repo is the source of truth after each pull.
install_boinc_file "${src}/hosts.list" /etc/boinc-client/hosts.list
tmp="$(mktemp)"
grep -vE '^[[:space:]]*(#|$)' "${src}/hosts.list" >"$tmp" || true
if [[ ! -s "$tmp" ]]; then
    warn "files/boinc/hosts.list has no live hosts; remote manager will be denied until you add some"
fi
install_boinc_file "$tmp" "${boinc_dir}/remote_hosts.cfg"
rm -f "$tmp"

install_boinc_file "${src}/find-boinccmd.sh" /usr/local/bin/find-boinccmd.sh 0644
install_boinc_file "${src}/boinc-config.sh" /usr/local/bin/boinc-config.sh 0755
install_boinc_file "${src}/boinc-status.sh" /usr/local/bin/boinc-status.sh 0755
install_boinc_file "${src}/boinc-status-all.sh" /usr/local/bin/boinc-status-all.sh 0755

if getent group boinc >/dev/null; then
    if ! id -nG "${DOTFILES_USER}" | grep -qw boinc; then
        log "add ${DOTFILES_USER} to boinc group"
        sudo usermod -aG boinc "${DOTFILES_USER}"
    fi
fi

ensure_systemd_dropin boinc-client.service yield-to-workloads $'[Service]\nNice=10\nCPUWeight=idle\nIOWeight=25\nOOMScoreAdjust=400\n'

enable_service boinc-client.service
if [[ "$boinc_changed" -eq 1 ]] || ! systemctl is-active --quiet boinc-client.service; then
    log "restart boinc-client to load repo files"
    run sudo systemctl restart boinc-client.service || run sudo systemctl start boinc-client.service
    sleep 2
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
    sudo BOINC_SECRET="$secret" /usr/local/bin/boinc-config.sh || \
        warn "Science United attach failed; retry with sudo /usr/local/bin/boinc-config.sh"
else
    warn "Science United skipped until ${secret} has the login fields"
fi
log "fleet status: sudo /usr/local/bin/boinc-status-all.sh"
