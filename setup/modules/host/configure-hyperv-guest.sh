#!/usr/bin/env bash
# Hyper-V guest subrole. Server pulls it in with @subrole.hyperv-guest.
# Other roles can use that line or --enable-subrole hyperv-guest.
#
# systemd-detect-virt must print "microsoft". Any other result, including
# a missing detector, returns before packages or files change.
#
# OpenMandriva does not ship a hyperv-daemons package. Rock znver1 and
# cooker znver1 publish hyperv-tools (checked: 6.14.2-3 and 7.2.9-1).
# That package owns:
#   hypervkvpd.service   KVP, the channel Hyper-V reads for the guest IP
#   hypervvssd.service   VSS
#   hypervfcopyd.service file copy
# Those units ExecStart /usr/sbin/hypervkvpd, hypervvssd, and hypervfcopyd.
# The package installs /usr/bin/hv_kvp_daemon, hv_vss_daemon, and
# hv_fcopy_uio_daemon instead, and the units have no [Install] section.
# Udev wants them when the vmbus devices appear. A drop-in points each
# unit at the binary the package owns, and this module starts them.
#
# chrony comes from the extra repo (enable-rock-repos). The unit is
# chronyd.service. Hyper-V time sync stays in hv_utils. That module also
# publishes the KVP, VSS, and file-copy devices, so it is not blacklisted
# and the host integration service is left on. chronyd is NTP while the
# guest is running; hv_utils still steps the clock at boot and after
# resume. If the two fight, turn off Time synchronization on the VM in
# Hyper-V rather than changing this module.
#
# /etc/dracut.conf.d/hyperv-guest.conf forces hv_vmbus, hv_storvsc,
# hv_netvsc, and hv_utils into the initramfs. dracut -f runs only when
# that file changes. A dry run may point HYPERV_DRACUT_CONF at a file
# under /tmp. A real role run always writes the path above.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/lib.sh"

require_user

virt=""
if command -v systemd-detect-virt >/dev/null 2>&1; then
    virt="$(systemd-detect-virt 2>/dev/null || true)"
fi
if [[ "$virt" != "microsoft" ]]; then
    log "not a Hyper-V guest (${virt:-unknown}); skipping"
    exit 0
fi

if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
    pick_pkg hyperv-tools >/dev/null \
        || die "hyperv-tools is not available. OpenMandriva publishes the KVP, VSS, and file-copy guest services as hyperv-tools, not hyperv-daemons"
    pick_pkg chrony >/dev/null \
        || die "chrony is not available. It is in the OpenMandriva extra repo, which enable-rock-repos turns on"
fi
ensure_packages hyperv-tools chrony

quiesce_other_ntp() {
    local unit state
    for unit in systemd-timesyncd.service ntpd.service ntp.service; do
        state="$(systemctl is-enabled "$unit" 2>/dev/null || true)"
        if [[ "$state" == "enabled" || "$state" == "enabled-runtime" ]]; then
            log "disable ${unit}"
            run sudo systemctl disable --now "$unit"
        elif [[ "$state" == "static" ]] && systemctl is-active --quiet "$unit"; then
            log "stop ${unit}"
            run sudo systemctl stop "$unit"
        fi
    done
}

start_unit() {
    local unit="$1"
    if systemctl is-active --quiet "$unit"; then
        return 0
    fi
    log "start ${unit}"
    sudo systemctl start "$unit" || die "could not start ${unit}"
}

restart_unit() {
    local unit="$1"
    if systemctl is-active --quiet "$unit"; then
        log "restart ${unit}"
        sudo systemctl restart "$unit" || die "could not restart ${unit}"
        return 0
    fi
    start_unit "$unit"
}

current_exec_path() {
    local show="$1"
    show="$(systemctl show -p ExecStart --value "$show" 2>/dev/null || true)"
    show="${show#*path=}"
    show="${show%% *}"
    show="${show%%;*}"
    printf '%s\n' "$show"
}

# Fedora unit names, kernel tools/hv binaries. Both pairs are what
# hyperv-tools 6.14.2-3 (Rock) and 7.2.9-1 (cooker) ship.
hyperv_unit_bin() {
    case "$1" in
        hypervkvpd.service) printf '%s\n' /usr/bin/hv_kvp_daemon ;;
        hypervvssd.service) printf '%s\n' /usr/bin/hv_vss_daemon ;;
        hypervfcopyd.service) printf '%s\n' /usr/bin/hv_fcopy_uio_daemon ;;
        *) return 1 ;;
    esac
}

point_unit_at() {
    local unit="$1"
    local bin="$2"
    local body
    body="[Service]"$'\n'"ExecStart="$'\n'"ExecStart=${bin} -n"
    ensure_systemd_dropin "$unit" exec-path "$body"
}

install_hyperv_services() {
    local unit bin path
    local -a known=(hypervkvpd.service hypervvssd.service hypervfcopyd.service)

    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        for unit in "${known[@]}"; do
            log "dry-run: drop-in ${unit} -> $(hyperv_unit_bin "$unit")"
            log "dry-run: start ${unit}"
        done
        return 0
    fi

    run sudo mkdir -p /var/lib/hyperv
    for unit in "${known[@]}"; do
        systemctl cat "$unit" >/dev/null 2>&1 || die "hyperv-tools did not install ${unit}"
        bin="$(hyperv_unit_bin "$unit")"
        [[ -x "$bin" ]] || die "hyperv-tools did not install ${bin}"
        path="$(current_exec_path "$unit")"
        if [[ "$path" == "$bin" ]]; then
            start_unit "$unit"
            continue
        fi
        point_unit_at "$unit" "$bin"
        if [[ "$(current_exec_path "$unit")" != "$bin" ]]; then
            run sudo systemctl daemon-reload
        fi
        [[ "$(current_exec_path "$unit")" == "$bin" ]] || die "${unit} ExecStart is still ${path}"
        restart_unit "$unit"
    done

    while IFS= read -r unit || [[ -n "$unit" ]]; do
        [[ -n "$unit" ]] || continue
        case "$unit" in
            hypervkvpd.service | hypervvssd.service | hypervfcopyd.service) continue ;;
        esac
        path="$(current_exec_path "$unit")"
        if [[ -n "$path" && -x "$path" ]]; then
            log "extra hyperv unit ${unit}"
            start_unit "$unit"
            continue
        fi
        die "hyperv-tools ships ${unit} with ExecStart ${path:-unknown}, which is not installed"
    done < <(rpm -ql hyperv-tools | sed -n 's|.*/systemd/system/\([^/]*\.service\)$|\1|p')
}

install_hyperv_dracut() {
    local src="${SETUP_FILES_DIR}/hyperv/hyperv-guest.conf"
    local dest="/etc/dracut.conf.d/hyperv-guest.conf"
    local backup=""

    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" && -n "${HYPERV_DRACUT_CONF:-}" ]]; then
        case "$HYPERV_DRACUT_CONF" in
            /tmp/*) dest="$HYPERV_DRACUT_CONF" ;;
            *) die "HYPERV_DRACUT_CONF must sit under /tmp" ;;
        esac
    fi
    [[ -f "$src" ]] || die "missing ${src}"
    if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
        return 0
    fi
    log "write ${dest}"
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        log "dry-run: dracut -f"
        return 0
    fi
    sudo mkdir -p /etc/dracut.conf.d
    if [[ -f "$dest" ]]; then
        backup="$(mktemp)"
        cat "$dest" >"$backup"
    fi
    sudo install -m 0644 "$src" "$dest"
    if ! command -v dracut >/dev/null 2>&1; then
        warn "dracut is not installed; ${dest} will apply on the next kernel install"
        rm -f "$backup"
        return 0
    fi
    log "rebuild initramfs"
    if sudo dracut -f; then
        rm -f "$backup"
        return 0
    fi
    warn "dracut -f failed; restoring ${dest} so the next run retries"
    if [[ -n "$backup" ]]; then
        sudo install -m 0644 "$backup" "$dest"
        rm -f "$backup"
    else
        sudo rm -f "$dest"
    fi
    die "dracut -f failed"
}

start_chronyd() {
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        log "dry-run: start chronyd.service"
        return 0
    fi
    start_unit chronyd.service
}

quiesce_other_ntp
enable_service chronyd.service
start_chronyd
install_hyperv_services
install_hyperv_dracut
