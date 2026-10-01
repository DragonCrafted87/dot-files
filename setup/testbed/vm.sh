#!/usr/bin/env bash
# Libvirt bench for role reset. The golden disk is an installed
# OpenMandriva system. Clones are throwaway overlays.
set -euo pipefail

IMAGE_DIR="${DOTFILES_TESTBED_IMAGE_DIR:-/var/lib/libvirt/images/dot-files}"
GOLDEN_NAME="dotfiles-golden"
CLONE_NAME="dotfiles-clone"
GOLDEN_DISK="${IMAGE_DIR}/golden.qcow2"
CLONE_DISK="${IMAGE_DIR}/clone.qcow2"
BACKUP_DIR="${DOTFILES_TESTBED_BACKUP_DIR:-/home/dragon/network/storage/virtual-machines/dot-files}"
ISO="${DOTFILES_TESTBED_ISO:-${HOME}/network/storage/disc-images/pc/openmandriva-6.0-plasma6-wayland.znver1.iso}"
KEY_DIR="${HOME}/.local/share/dot-files/testbed"
KEY_FILE="${KEY_DIR}/id_ed25519"
PASS_FILE="${KEY_DIR}/calamares-password"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"
PACKAGES=(qemu-kvm libvirt-utils virt-install virtiofsd ovmf)

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

warn() {
    printf 'warning: %s\n' "$*" >&2
}

# Copy SRC into DEST_DIR/golden.qcow2, keeping one .bak generation.
# A missing DEST_DIR fails before anything is written.
rotate_backup() {
    local src="$1"
    local dest_dir="$2"
    local new="${dest_dir}/golden.qcow2.new"
    local dest="${dest_dir}/golden.qcow2"
    local bak="${dest_dir}/golden.qcow2.bak"

    [[ -d "$dest_dir" ]] || return 1
    [[ -f "$src" ]] || return 1
    if [[ -r "$src" ]]; then
        cp -f -- "$src" "$new" || {
            rm -f -- "$new"
            return 1
        }
    else
        sudo cp -f -- "$src" "$new" || {
            sudo rm -f -- "$new"
            return 1
        }
    fi
    if [[ -e "$dest" ]]; then
        mv -f -- "$dest" "$bak"
    fi
    mv -f -- "$new" "$dest"
}

# up may proceed only when the golden domain is not running and the
# share copy of the golden disk exists.
up_allowed() {
    local golden_state="$1"
    local backup_file="$2"
    [[ "$golden_state" != "running" ]] || return 1
    [[ -f "$backup_file" ]] || return 1
}

domain_state() {
    sudo virsh domstate "$1" 2>/dev/null || true
}

packages_missing() {
    local pkg
    for pkg in "${PACKAGES[@]}"; do
        rpm -q "$pkg" >/dev/null 2>&1 || return 0
    done
    return 1
}

print_package_line() {
    printf 'sudo dnf install'
    printf ' %s' "${PACKAGES[@]}"
    printf '\n'
}

cmd_host_check() {
    local ok=0
    if packages_missing; then
        print_package_line
        ok=1
    fi
    command -v virsh >/dev/null 2>&1 || ok=1
    command -v virt-install >/dev/null 2>&1 || ok=1
    if ! systemctl is-active --quiet libvirtd; then
        printf 'libvirtd is not active\n'
        ok=1
    fi
    if [[ ! -e /dev/kvm ]]; then
        printf '/dev/kvm is missing\n'
        ok=1
    fi
    return "$ok"
}

require_host() {
    if packages_missing || ! command -v virsh >/dev/null 2>&1 \
        || ! command -v virt-install >/dev/null 2>&1; then
        print_package_line >&2
        die "libvirt packages are not installed"
    fi
    [[ -e /dev/kvm ]] || die "/dev/kvm is missing"
    sudo systemctl enable --now libvirtd
}

ensure_key() {
    mkdir -p "$KEY_DIR"
    if [[ ! -f "$KEY_FILE" ]]; then
        ssh-keygen -t ed25519 -N '' -f "$KEY_FILE" >/dev/null
    fi
}

ensure_password() {
    mkdir -p "$KEY_DIR"
    if [[ ! -f "$PASS_FILE" ]]; then
        umask 077
        openssl rand -base64 24 >"$PASS_FILE"
        chmod 0600 "$PASS_FILE"
    fi
}

guest_ip() {
    local name="$1"
    sudo virsh domifaddr "$name" --source lease 2>/dev/null \
        | awk '/ipv4/ {print $4}' | head -1 | cut -d/ -f1
}

ssh_guest() {
    local name="$1"
    shift
    local ip ask
    ip="$(guest_ip "$name")"
    [[ -n "$ip" ]] || die "no address for ${name}"
    ensure_key
    ask="$(mktemp)"
    chmod 0700 "$ask"
    cat >"$ask" <<EOF
#!/bin/sh
cat "${PASS_FILE}"
EOF
    # shellcheck disable=SC2064
    trap "rm -f -- '${ask}'" RETURN
    DISPLAY=none SSH_ASKPASS="$ask" SSH_ASKPASS_REQUIRE=force \
        ssh -i "$KEY_FILE" \
        -o PreferredAuthentications=publickey,password \
        -o StrictHostKeyChecking=accept-new \
        -o UserKnownHostsFile="${KEY_DIR}/known_hosts" \
        "dragon@${ip}" "$@"
}

wait_shutoff() {
    local name="$1"
    local i state
    for i in $(seq 1 60); do
        state="$(domain_state "$name")"
        [[ "$state" == "shut off" ]] && return 0
        sleep 2
    done
    die "${name} did not shut off (state: ${state})"
}

cmd_install() {
    require_host
    [[ -e "$ISO" ]] || die "missing ISO ${ISO}"
    if [[ -e "$GOLDEN_DISK" ]]; then
        die "golden disk already exists at ${GOLDEN_DISK}"
    fi
    ensure_password
    sudo mkdir -p "$IMAGE_DIR"
    sudo virt-install \
        --name "$GOLDEN_NAME" \
        --memory 8192 \
        --vcpus 4 \
        --cpu host-passthrough \
        --disk "path=${GOLDEN_DISK},size=80,format=qcow2,bus=virtio" \
        --cdrom "$ISO" \
        --os-variant linux2022 \
        --graphics spice \
        --boot uefi \
        --network network=default \
        --noautoconsole \
        --noreboot \
        --wait 0
    if [[ "${DOTFILES_TESTBED_BOOT_ONLY:-0}" == "1" ]]; then
        return 0
    fi
    drive_calamares
}

# Task 4 replaces this with the graphical session. Until then, install
# only boots when DOTFILES_TESTBED_BOOT_ONLY=1.
drive_calamares() {
    die "Calamares is not driven yet"
}

write_repo_mount() {
    ssh_guest "$GOLDEN_NAME" "sudo tee /etc/systemd/system/dotfiles-repo.service >/dev/null" <<'EOF'
[Unit]
Description=Mount the dot-files checkout
After=local-fs.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/mkdir -p /home/dragon/dot-files
ExecStart=/usr/bin/mount -t virtiofs dotfiles /home/dragon/dot-files

[Install]
WantedBy=multi-user.target
EOF
    ssh_guest "$GOLDEN_NAME" sudo systemctl enable dotfiles-repo.service
}

cmd_seal() {
    local host
    require_host
    ensure_key
    ensure_password
    host="$(ssh_guest "$GOLDEN_NAME" hostname -s)"
    host="${host//$'\r'/}"
    [[ "$host" == "testbed" ]] || die "hostname is ${host}, want testbed"
    ssh_guest "$GOLDEN_NAME" "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
    ssh_guest "$GOLDEN_NAME" "cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" \
        <"${KEY_FILE}.pub"
    write_repo_mount
    sudo virsh shutdown "$GOLDEN_NAME"
    wait_shutoff "$GOLDEN_NAME"
    rotate_backup "$GOLDEN_DISK" "$BACKUP_DIR"
}

cmd_backup() {
    local state
    state="$(domain_state "$GOLDEN_NAME")"
    [[ "$state" != "running" ]] || die "shut the golden domain down before backup"
    [[ -f "$GOLDEN_DISK" ]] || die "missing ${GOLDEN_DISK}"
    rotate_backup "$GOLDEN_DISK" "$BACKUP_DIR"
}

clone_filesystem_args() {
    printf '%s' "type=mount,driver.type=virtiofs,source=${REPO},target=dotfiles,accessmode=passthrough"
}

cmd_up() {
    local state
    require_host
    state="$(domain_state "$GOLDEN_NAME")"
    if ! up_allowed "$state" "${BACKUP_DIR}/golden.qcow2"; then
        die "refusing to boot the clone (golden state: ${state:-absent})"
    fi
    [[ -f "$GOLDEN_DISK" ]] || die "missing ${GOLDEN_DISK}"
    if [[ ! -f "$CLONE_DISK" ]]; then
        sudo qemu-img create -f qcow2 -b "$GOLDEN_DISK" -F qcow2 "$CLONE_DISK"
    fi
    if [[ -z "$(domain_state "$CLONE_NAME")" ]]; then
        sudo virt-install \
            --name "$CLONE_NAME" \
            --memory 8192 \
            --vcpus 4 \
            --cpu host-passthrough \
            --disk "path=${CLONE_DISK},bus=virtio" \
            --import \
            --os-variant linux2022 \
            --graphics spice \
            --boot uefi \
            --network network=default \
            --memorybacking source.type=memfd,access.mode=shared \
            --filesystem "$(clone_filesystem_args)" \
            --noautoconsole \
            --wait 0
    else
        sudo virsh start "$CLONE_NAME"
    fi
}

cmd_ssh() {
    ensure_key
    ssh_guest "$CLONE_NAME" "$@"
}

cmd_down() {
    sudo virsh shutdown "$CLONE_NAME"
    wait_shutoff "$CLONE_NAME"
}

cmd_destroy_clone() {
    if [[ -n "$(domain_state "$CLONE_NAME")" ]]; then
        sudo virsh destroy "$CLONE_NAME" >/dev/null 2>&1 || true
        sudo virsh undefine "$CLONE_NAME" --nvram >/dev/null 2>&1 || \
            sudo virsh undefine "$CLONE_NAME" >/dev/null 2>&1 || true
    fi
    if [[ -e "$CLONE_DISK" ]]; then
        sudo rm -f -- "$CLONE_DISK"
    fi
}

usage() {
    cat <<EOF
usage: $(basename "$0") <command>

  host-check
  install
  seal
  backup
  up
  ssh [command...]
  down
  destroy-clone
EOF
    exit 2
}

main() {
    local cmd="${1:-}"
    [[ -n "$cmd" ]] || usage
    shift
    case "$cmd" in
        host-check) cmd_host_check ;;
        install) cmd_install "$@" ;;
        seal) cmd_seal "$@" ;;
        backup) cmd_backup "$@" ;;
        up) cmd_up "$@" ;;
        ssh)
            if [[ "$#" -eq 0 ]]; then
                ssh_guest "$CLONE_NAME"
            else
                cmd_ssh "$@"
            fi
            ;;
        down) cmd_down "$@" ;;
        destroy-clone) cmd_destroy_clone "$@" ;;
        *) die "unknown command ${cmd}" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
