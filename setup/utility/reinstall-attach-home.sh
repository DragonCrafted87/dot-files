#!/usr/bin/env bash
# Run from the OpenMandriva live ISO (Ventoy) after a root-disk reinstall,
# or from the first boot of the new root before /home is the LVM volume.
#
# Activates VG lv-home, mounts LV home over /home on the installed root,
# writes fstab, disables SDDM, installs git.
#
#   sudo bash reinstall-attach-home.sh
#   sudo HOME_VG=lv-home HOME_LV=home bash reinstall-attach-home.sh
#
# Self-contained: copy this file onto the Ventoy stick. It does not need
# the rest of the repo.

set -euo pipefail

HOME_VG="${HOME_VG:-lv-home}"
HOME_LV="${HOME_LV:-home}"
HOME_DEV="/dev/${HOME_VG}/${HOME_LV}"
# PVs that belong to the home VG — never treat these as the OS root disk.
HOME_PVS="${HOME_PVS:-/dev/nvme1n1 /dev/nvme2n1}"
NEWROOT="${NEWROOT:-/mnt/newroot}"
USER_NAME="${USER_NAME:-dragon}"

log() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "run as root (sudo $0)"

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
    local name fstype type_ parent uuid
    # Prefer partitions that contain an /etc/os-release once mounted,
    # skip LVM PVs, skip the live medium, skip the home LV.
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
        # skip already-mounted live root
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
        # Keep the mountpoint itself.
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

# -- live ISO: operate on the installed root ----------------------
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
    mount_home_on "$NEWROOT"
    write_home_fstab "${NEWROOT}/etc/fstab"
    disable_sddm_on "$NEWROOT"
    install_git_on "$NEWROOT"
    log "done. reboot into the installed disk. /home is ${HOME_DEV}"
    log "then: sudo dnf install -y git   # if the chroot install was skipped"
    log "      ~/dot-files/setup/role.sh workstation"
    exit 0
fi

# -- already on the installed system ------------------------------
log "installed system (not live)"
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

write_home_fstab /etc/fstab
disable_sddm_on /
install_git_on /
log "done. SDDM disabled, /home is ${HOME_DEV}"
