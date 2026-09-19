#!/usr/bin/env bash
# Dump rpm names from a live system or from an OpenMandriva LiveOS ISO.
#
#   sudo bash harvest-iso-packages.sh -o setup/files/iso-installed.txt
#   sudo bash harvest-iso-packages.sh --iso ~/Downloads/openmandriva-6.0-plasma6.x11-slim.x86_64.iso
#   sudo bash harvest-iso-packages.sh --iso FILE -o setup/files/iso-installed.txt

set -euo pipefail

out=""
iso=""

usage() {
    cat >&2 <<EOF
usage: $0 [-o FILE] [--iso ISO]
  no --iso   harvest rpm -qa from the running system (live ISO session)
  --iso FILE mount the ISO + LiveOS/squashfs.img and harvest that root
EOF
    exit 1
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -o | --output)
            [[ "$#" -ge 2 ]] || usage
            out="$2"
            shift
            ;;
        --iso)
            [[ "$#" -ge 2 ]] || usage
            iso="$2"
            shift
            ;;
        -h | --help)
            usage
            ;;
        *)
            if [[ -z "$out" && "$1" != -* ]]; then
                out="$1"
            else
                usage
            fi
            ;;
    esac
    shift
done

out="${out:-/dev/stdout}"

write_list() {
    local root="$1"
    local src="$2"
    {
        printf '# harvested %s\n' "$(date -Iseconds)"
        printf '# source=%s\n' "$src"
        if [[ -f "${root}/etc/os-release" ]]; then
            # shellcheck disable=SC1091
            . "${root}/etc/os-release"
            printf '# os=%s version=%s\n' "${NAME:-unknown}" "${VERSION_ID:-unknown}"
        fi
        rpm --root "$root" -qa --qf '%{name}\n' | sort -u
    } >"$out"
}

if [[ -z "$iso" ]]; then
    write_list / "running-system rpm -qa"
else
    [[ -f "$iso" ]] || {
        echo "error: iso not found: $iso" >&2
        exit 1
    }
    [[ "$(id -u)" -eq 0 ]] || {
        echo "error: --iso needs root to loop-mount" >&2
        exit 1
    }
    mnt_iso="$(mktemp -d /tmp/iso.XXXXXX)"
    mnt_sq="$(mktemp -d /tmp/sq.XXXXXX)"
    cleanup() {
        umount "$mnt_sq" 2>/dev/null || true
        umount "$mnt_iso" 2>/dev/null || true
        rmdir "$mnt_sq" "$mnt_iso" 2>/dev/null || true
    }
    trap cleanup EXIT
    mount -o loop,ro "$iso" "$mnt_iso"
    if [[ ! -f "${mnt_iso}/LiveOS/squashfs.img" ]]; then
        echo "error: no LiveOS/squashfs.img in $iso" >&2
        exit 1
    fi
    mount -o loop,ro "${mnt_iso}/LiveOS/squashfs.img" "$mnt_sq"
    # OM slim ISO is a full root inside the squash, not a nested rootfs.img.
    write_list "$mnt_sq" "$iso LiveOS/squashfs.img"
fi

if [[ "$out" != /dev/stdout ]]; then
    printf 'wrote %s (%s names)\n' "$out" "$(grep -cvE '^#' "$out" || true)" >&2
fi
