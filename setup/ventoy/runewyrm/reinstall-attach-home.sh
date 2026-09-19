#!/usr/bin/env bash
# runewyrm only. Copy this folder onto the Ventoy stick.
# Run from the OpenMandriva live ISO after a root-disk reinstall.
#
#   sudo bash reinstall-attach-home.sh
#
# Refuses to continue if the installed root's hostname is not runewyrm
# (installer defaults like localhost/openmandriva are allowed only when
# the LVM home already looks like runewyrm).

set -euo pipefail

EXPECTED_HOST="${EXPECTED_HOST:-runewyrm}"
HOME_VG="${HOME_VG:-lv-home}"
HOME_LV="${HOME_LV:-home}"
HOME_DEV="/dev/${HOME_VG}/${HOME_LV}"
HOME_PVS="${HOME_PVS:-/dev/nvme1n1 /dev/nvme2n1}"
NEWROOT="${NEWROOT:-/mnt/newroot}"
USER_NAME="${USER_NAME:-dragon}"

log() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "run as root (sudo $0)"

read_hostname() {
    local root="$1"
    local host=""
    if [[ -f "${root}/etc/hostname" ]]; then
        host="$(tr -d '[:space:]' <"${root}/etc/hostname")"
    fi
    if [[ -z "$host" && -f "${root}/etc/static-hostname" ]]; then
        host="$(tr -d '[:space:]' <"${root}/etc/static-hostname")"
    fi
    host="${host%%.*}"
    printf '%s\n' "$host"
}

is_generic_hostname() {
    case "$1" in
        "" | localhost | localhost.localdomain | openmandriva | omv | omv-live | livecd | live)
            return 0
            ;;
    esac
    return 1
}

home_looks_like_expected() {
    local home="$1"
    [[ -f "${home}/${USER_NAME}/.config/hypr/conf.d/hosts.d/${EXPECTED_HOST}.conf" ]] && return 0
    [[ -d "${home}/${USER_NAME}/games/multi-mc" ]] && return 0
    [[ -f "${home}/${USER_NAME}/.config/dot-files/role" ]] && return 0
    return 1
}

require_expected_host() {
    local root="$1"
    local host
    host="$(read_hostname "$root")"
    if [[ "$host" == "$EXPECTED_HOST" ]]; then
        log "hostname ${host} matches ${EXPECTED_HOST}"
        return 0
    fi
    if is_generic_hostname "$host" && home_looks_like_expected "${root}/home"; then
        log "hostname '${host}' is installer default; LVM home looks like ${EXPECTED_HOST}"
        return 0
    fi
    die "this script is ${EXPECTED_HOST}-only; installed hostname is '${host:-unset}'"
}

is_live() {
    if grep -Eqw 'rd.live|liveimg|overlay' /proc/cmdline 2>/dev/null; then
        return 0
    fi
    if findmnt -n -o FSTYPE / 2>/dev/null | grep -Eq 'overlay|squashfs'; then
        return 0
    fi
    if [[ -d /run/initramfs/live || -d /run/rootfsbase ]]; then
        return 0
    fi
    return 1
}

pv_is_home() {
    local dev="$1"
    local pv
    for pv in $HOME_PVS; do
        if [[ "$dev" == "$pv" || "$dev" == ${pv}p* ]]; then
            return 0
        fi
    done
    return 1
}

ensure_lvm_tools() {
    if command -v vgchange >/dev/null 2>&1; then
        return 0
    fi
    log "install lvm2"
    dnf install -y lvm2 || die "need lvm2 on the live image"
}

activate_vg() {
    log "scan and activate VG ${HOME_VG}"
    vgscan --mknodes || true
    pvscan --cache || true
    vgchange -ay "$HOME_VG" || die "could not activate ${HOME_VG}"
    [[ -b "$HOME_DEV" ]] || die "missing ${HOME_DEV} after vgchange"
    log "$(lvs --noheadings -o lv_path,lv_size "$HOME_DEV" | tr -s ' ')"
}

find_installed_root() {
    local name fstype type_ parent
    while read -r name fstype type_ parent; do
        [[ "$type_" == part || "$type_" == lvm ]] || continue
        [[ -n "$fstype" ]] || continue
        case "$fstype" in
            ext4 | ext3 | xfs | btrfs | f2fs) ;;
            *) continue ;;
        esac
        [[ "$name" == "$HOME_DEV" || "$name" == /dev/mapper/lv--home-home ]] && continue
        pv_is_home "$name" && continue
        pv_is_home "$parent" && continue
        if findmnt -n -o SOURCE / 2>/dev/null | grep -qx "$name"; then
            continue
        fi
        printf '%s\n' "$name"
    done < <(lsblk -lnpo NAME,FSTYPE,TYPE,PKNAME)
}

pick_root_dev() {
    local candidates=()
    local d
    mapfile -t candidates < <(find_installed_root)
    if [[ "${#candidates[@]}" -eq 0 ]]; then
        die "no installed root filesystem found (not on ${HOME_PVS})"
    fi
    if [[ "${#candidates[@]}" -eq 1 ]]; then
        printf '%s\n' "${candidates[0]}"
        return 0
    fi
    log "multiple root candidates; probing for /etc/os-release"
    local tmp probe=()
    tmp="$(mktemp -d)"
    for d in "${candidates[@]}"; do
        if mount -o ro "$d" "$tmp" 2>/dev/null; then
            if [[ -f "${tmp}/etc/os-release" && -d "${tmp}/home" ]]; then
                probe+=("$d")
            fi
            umount "$tmp" || true
        fi
    done
    rmdir "$tmp" || true
    if [[ "${#probe[@]}" -eq 1 ]]; then
        printf '%s\n' "${probe[0]}"
        return 0
    fi
    die "ambiguous root devices: ${candidates[*]}. Set ROOT_DEV=/dev/..."
}

fstab_has_home_lv() {
    local fstab="$1"
    grep -Eq "[[:space:]]/home[[:space:]]" "$fstab" \
        && grep -Eq "${HOME_VG}|${HOME_DEV}|lv--home-home" "$fstab"
}

write_home_fstab() {
    local fstab="$1"
    local uuid fstype
    uuid="$(blkid -s UUID -o value "$HOME_DEV")"
    fstype="$(blkid -s TYPE -o value "$HOME_DEV")"
    [[ -n "$uuid" && -n "$fstype" ]] || die "blkid failed on ${HOME_DEV}"
    if fstab_has_home_lv "$fstab"; then
        log "fstab already points /home at ${HOME_VG}"
        return 0
    fi
    if grep -Eq "[[:space:]]/home[[:space:]]" "$fstab"; then
        log "comment existing /home fstab line"
        sed -i -E 's|^([^#].*[[:space:]]/home[[:space:]].*)|# \1  # replaced by reinstall-attach-home|' "$fstab"
    fi
    log "add UUID=${uuid} /home ${fstype} to fstab"
    printf '\n# LVM home (%s) attached by reinstall-attach-home.sh\nUUID=%s /home %s defaults,x-systemd.device-timeout=30 0 2\n' \
        "$HOME_DEV" "$uuid" "$fstype" >>"$fstab"
}

disable_sddm_on() {
    local root="$1"
    log "disable SDDM on ${root}"
    systemctl --root="$root" disable sddm.service 2>/dev/null || true
    systemctl --root="$root" disable plasma6-sddm.service 2>/dev/null || true
    systemctl --root="$root" mask sddm.service 2>/dev/null || true
    systemctl --root="$root" mask plasma6-sddm.service 2>/dev/null || true
}

install_git_on() {
    local root="$1"
    if [[ -x "${root}/usr/bin/git" ]]; then
        log "git already present under ${root}"
        return 0
    fi
    log "install git in ${root}"
    if [[ "$root" == / ]]; then
        dnf install -y git curl
    else
        dnf --installroot="$root" install -y git curl || \
            chroot "$root" dnf install -y git curl || \
            warn "could not install git in ${root}; do it after reboot"
    fi
}

mount_home_on() {
    local root="$1"
    local home="${root}/home"
    mkdir -p "$home"
    if findmnt -n "$home" >/dev/null 2>&1; then
        local src
        src="$(findmnt -n -o SOURCE "$home")"
        if [[ "$src" == "$HOME_DEV" || "$src" == /dev/mapper/lv--home-home ]]; then
            log "${home} already mounted from ${src}"
            return 0
        fi
        log "unmount existing ${home} (${src})"
        umount "$home" || die "could not unmount ${home}"
    fi
    if [[ -d "$home" ]] && find "$home" -mindepth 1 -maxdepth 1 | grep -q .; then
        local aside="${home}.installer.$(date +%F-%H%M%S)"
        log "move installer ${home} -> ${aside}"
        mkdir -p "$aside"
        find "$home" -mindepth 1 -maxdepth 1 -exec mv {} "$aside" \;
    fi
    log "mount ${HOME_DEV} on ${home}"
    mount "$HOME_DEV" "$home"
    if [[ ! -d "${home}/${USER_NAME}" ]]; then
        warn "mounted home has no ${USER_NAME}/; check the LV"
    else
        log "home user dir ${home}/${USER_NAME} present"
    fi
}

if is_live; then
    log "live environment detected"
    ensure_lvm_tools
    activate_vg
    ROOT_DEV="${ROOT_DEV:-$(pick_root_dev)}"
    log "installed root ${ROOT_DEV}"
    mkdir -p "$NEWROOT"
    if ! findmnt -n "$NEWROOT" >/dev/null 2>&1; then
        mount "$ROOT_DEV" "$NEWROOT"
    fi
    # Hostname may live on the installer root; identity also lives on LVM home.
    host_now="$(read_hostname "$NEWROOT")"
    if ! is_generic_hostname "$host_now" && [[ "$host_now" != "$EXPECTED_HOST" ]]; then
        die "this script is ${EXPECTED_HOST}-only; installed hostname is '${host_now}'"
    fi
    mount_home_on "$NEWROOT"
    require_expected_host "$NEWROOT"
    write_home_fstab "${NEWROOT}/etc/fstab"
    disable_sddm_on "$NEWROOT"
    install_git_on "$NEWROOT"
    log "done. reboot into the installed disk. /home is ${HOME_DEV}"
    exit 0
fi

log "installed system (not live)"
host_now="$(read_hostname /)"
if ! is_generic_hostname "$host_now" && [[ "$host_now" != "$EXPECTED_HOST" ]]; then
    die "this script is ${EXPECTED_HOST}-only; hostname is '${host_now}'"
fi
ensure_lvm_tools
activate_vg

if findmnt -n /home >/dev/null 2>&1; then
    src="$(findmnt -n -o SOURCE /home)"
    if [[ "$src" == "$HOME_DEV" || "$src" == /dev/mapper/lv--home-home ]]; then
        log "/home already on ${src}"
    else
        die "/home is ${src}, not ${HOME_DEV}. Log out every user and rerun, or use the live ISO."
    fi
else
    mount_home_on /
fi
require_expected_host /
write_home_fstab /etc/fstab
disable_sddm_on /
install_git_on /
log "done. SDDM disabled, /home is ${HOME_DEV}"
