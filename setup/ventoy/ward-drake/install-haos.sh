#!/usr/bin/env bash
# Write Home Assistant OS onto ward-drake's internal disk.
# Boot the OpenMandriva live image from Ventoy on the NUC, then:
#
#   sudo bash /path/on/ventoy/ward-drake/install-haos.sh
#
# The x86-64 HAOS release is a raw disk image, not an installer.
# This script streams that image onto one whole disk. It refuses the
# Ventoy stick, any disk that holds the running system, and any disk
# whose model is not the NUC's WD SN550 (WDS500G3X0C) unless
# HA_EXPECT_MODEL is set to the model lsblk prints.
#
# Does not copy the 2021 Home Assistant config. First boot is the
# onboarding screen. Set the hostname to ward-drake after that.

set -euo pipefail

EXPECT_MODEL="${HA_EXPECT_MODEL:-WDS500G3X0C}"
CONFIRM='wipe ward-drake'
KNOWN_SHA256_18_3='121fcf49d373e6cfa68ce2176d740980b8856de263e876b9f6dfb299cbd51ef8'

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "run as root (sudo bash $0)"

is_live() {
    if grep -Eqw 'rd.live|liveimg|overlay' /proc/cmdline 2>/dev/null; then
        return 0
    fi
    if findmnt -n -o FSTYPE / 2>/dev/null | grep -Eq 'overlay|squashfs'; then
        return 0
    fi
    [[ -d /run/initramfs/live || -d /run/rootfsbase ]]
}

is_live || die "this only runs from the OpenMandriva live image, not an installed system"

command -v xzcat >/dev/null 2>&1 || die "xzcat is missing; install xz on the live image"
command -v dd >/dev/null 2>&1 || die "dd is missing"
command -v swapoff >/dev/null 2>&1 || die "swapoff is missing"

parent_disk() {
    local node="$1"
    local pk
    pk="$(lsblk -no PKNAME "$node" 2>/dev/null | head -n 1 || true)"
    if [[ -n "$pk" ]]; then
        printf '/dev/%s\n' "$pk"
    else
        printf '%s\n' "$node"
    fi
}

ventoy_partition() {
    local name label
    while read -r name label; do
        if [[ "$label" == "Ventoy" ]]; then
            printf '%s\n' "$name"
            return 0
        fi
    done < <(lsblk -rpno NAME,LABEL)
    return 1
}

VENTOY_PART="$(ventoy_partition)" || die "no partition labeled Ventoy. Plug the stick in and try again."
VENTOY_DISK="$(parent_disk "$VENTOY_PART")"
VENTOY_MNT="$(findmnt -rn -o TARGET -S "$VENTOY_PART" | head -n 1 || true)"
if [[ -z "$VENTOY_MNT" ]]; then
    VENTOY_MNT=/mnt/ventoy
    mkdir -p "$VENTOY_MNT"
    mount -o ro "$VENTOY_PART" "$VENTOY_MNT"
fi
log "Ventoy is ${VENTOY_DISK} mounted at ${VENTOY_MNT}"

if [[ -n "${HA_IMAGE:-}" ]]; then
    IMAGE="$HA_IMAGE"
else
    shopt -s nullglob
    candidates=("${VENTOY_MNT}/raw-disc-images/"haos_generic-x86-64-*.img.xz)
    shopt -u nullglob
    [[ ${#candidates[@]} -gt 0 ]] || die "no haos_generic-x86-64-*.img.xz under ${VENTOY_MNT}/raw-disc-images"
    IMAGE="$(printf '%s\n' "${candidates[@]}" | sort -V | tail -n 1)"
fi
[[ -f "$IMAGE" ]] || die "image not found: ${IMAGE}"
[[ "$(basename "$IMAGE")" == haos_generic-x86-64-*.img.xz ]] || die "refusing ${IMAGE}; want haos_generic-x86-64-*.img.xz"

base="$(basename "$IMAGE")"
expect_sha=""
case "$base" in
    haos_generic-x86-64-18.3.img.xz) expect_sha="$KNOWN_SHA256_18_3" ;;
esac
if [[ -z "$expect_sha" && -f "${IMAGE}.sha256" ]]; then
    expect_sha="$(awk '{print $1}' "${IMAGE}.sha256")"
fi
[[ -n "$expect_sha" ]] || die "no checksum for ${base}. Put one in ${IMAGE}.sha256"
log "checking ${base}"
actual_sha="$(sha256sum "$IMAGE" | awk '{print $1}')"
[[ "$actual_sha" == "$expect_sha" ]] || die "checksum mismatch for ${IMAGE}"

log "disks:"
lsblk -d -o NAME,SIZE,MODEL,TRAN,TYPE | sed 's/^/    /'

if [[ -n "${1:-}" ]]; then
    TARGET="$1"
else
    printf 'Whole disk to overwrite (for example nvme0n1): '
    read -r TARGET
fi
[[ -n "$TARGET" ]] || die "no disk given"
[[ "$TARGET" != /dev/* ]] && TARGET="/dev/${TARGET}"
[[ -b "$TARGET" ]] || die "${TARGET} is not a block device"
[[ "$(lsblk -dno TYPE "$TARGET")" == "disk" ]] || die "${TARGET} is not a whole disk. Do not pass a partition."

target_real="$(readlink -f "$TARGET")"
ventoy_real="$(readlink -f "$VENTOY_DISK")"
[[ "$target_real" != "$ventoy_real" ]] || die "refusing to write the Ventoy stick ${VENTOY_DISK}"

while read -r mp; do
    [[ -z "$mp" ]] && continue
    case "$mp" in
        / | /boot | /boot/efi | /home | /run | "$VENTOY_MNT" | /mnt/ventoy)
            die "${TARGET} is mounted at ${mp}. That is not the NUC data disk."
            ;;
    esac
done < <(lsblk -nr -o MOUNTPOINT "$TARGET")

model="$(lsblk -ndo MODEL "$TARGET" | tr -d '[:space:]')"
[[ "$model" == *"$EXPECT_MODEL"* ]] || die "${TARGET} model is '${model}', expected '${EXPECT_MODEL}'. Set HA_EXPECT_MODEL only when lsblk shows the NUC disk."

printf '\nThis erases %s (%s, %s) and writes %s\n' \
    "$TARGET" "$model" "$(lsblk -ndo SIZE "$TARGET")" "$(basename "$IMAGE")"
printf 'Type "%s" to continue: ' "$CONFIRM"
read -r answer
[[ "$answer" == "$CONFIRM" ]] || die "aborted"

while read -r dev mp; do
    [[ -z "$mp" ]] && continue
    if [[ "$mp" == "[SWAP]" ]]; then
        [[ -n "$dev" ]] || die "swap on ${TARGET} has no device path"
        log "swapoff ${dev}"
        swapoff "$dev"
        continue
    fi
    log "unmounting ${mp}"
    umount "$mp"
done < <(lsblk -nrp -o NAME,MOUNTPOINT "$TARGET")

log "writing image"
xzcat "$IMAGE" | dd of="$TARGET" bs=4M conv=fsync status=progress
sync
blockdev --rereadpt "$TARGET" 2>/dev/null || true

log "done. Unplug Ventoy and boot the internal disk."
log "Onboarding is http://homeassistant.local:8123"
log "Set the hostname to ward-drake. Leave the 2021 config on castellan."
