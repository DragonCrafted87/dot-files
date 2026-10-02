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
# gir and osinfo-db are what let virt-install import Libosinfo and
# resolve --os-variant. The C library alone is not enough.
PACKAGES=(qemu-kvm qemu-img libvirt-utils virt-install virtiofsd ovmf lib64osinfo-gir1.0 osinfo-db)

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
    if [[ -r "$src" ]]; then
        cp --sparse=always -f -- "$src" "$new" || {
            rm -f -- "$new"
            return 1
        }
    elif sudo test -f "$src"; then
        sudo cp --sparse=always -f -- "$src" "$new" || {
            sudo rm -f -- "$new"
            return 1
        }
    else
        return 1
    fi
    if [[ -e "$dest" ]]; then
        mv -f -- "$dest" "$bak"
    fi
    mv -f -- "$new" "$dest"
}

# The golden qcow2 is safe to use as a backing file only when the
# domain is shut off, or libvirt has no such domain. paused, in
# shutdown, and an unreadable hypervisor still have the file open.
golden_is_idle() {
    local golden_state="$1"
    [[ "$golden_state" == "shut off" || "$golden_state" == "absent" ]]
}

up_allowed() {
    local golden_state="$1"
    local backup_file="$2"
    golden_is_idle "$golden_state" || return 1
    [[ -f "$backup_file" ]] || return 1
}

# rc 0 returns virsh's state. "failed to get domain" means the name is
# not defined. Any other failure is unknown, so callers do not treat a
# broken hypervisor connection as a missing domain.
classify_domstate() {
    local rc="$1"
    local out="$2"
    local err="$3"
    if [[ "$rc" -eq 0 ]]; then
        printf '%s\n' "$out"
        return 0
    fi
    if [[ "$err" == *"failed to get domain"* ]]; then
        printf 'absent\n'
        return 0
    fi
    printf 'unknown\n'
}

domain_state() {
    local out err rc
    err="$(mktemp)"
    set +e
    out="$(sudo virsh domstate "$1" 2>"$err")"
    rc=$?
    set -e
    classify_domstate "$rc" "$out" "$(cat "$err")"
    rc=$?
    rm -f -- "$err"
    return "$rc"
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
        -o ForwardX11=no \
        -o ForwardAgent=no \
        -o ConnectTimeout=10 \
        "dragon@${ip}" "$@"
}

wait_shutoff() {
    local name="$1"
    local i state
    for i in $(seq 1 90); do
        state="$(domain_state "$name")"
        [[ "$state" == "shut off" ]] && return 0
        sleep 2
    done
    die "${name} did not shut off (state: ${state})"
}

cmd_install() {
    require_host
    [[ -e "$ISO" ]] || die "missing ISO ${ISO}"
    if [[ -e "$GOLDEN_DISK" ]] || sudo test -e "$GOLDEN_DISK"; then
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
        --graphics vnc,listen=127.0.0.1 \
        --video virtio \
        --sound none \
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

# Task 4 drives the live session. The ISO opens om-welcome, then
# Calamares. Graphics are a 1280x800 VNC framebuffer; one control (the
# erase-disk radio) does not take keyboard focus until it is clicked.
SHOT="${TMPDIR:-/tmp}/dotfiles-testbed-screen.png"

take_screenshot() {
    sudo virsh screenshot "$GOLDEN_NAME" "$SHOT" >/dev/null
}

send_key() {
    sudo virsh send-key "$GOLDEN_NAME" "$@" >/dev/null
}

send_text() {
    local text="$1" i char
    for ((i = 0; i < ${#text}; i++)); do
        char="${text:i:1}"
        case "$char" in
            [a-z]) send_key "KEY_${char^^}" ;;
            [A-Z]) send_key KEY_LEFTSHIFT "KEY_${char}" ;;
            [0-9]) send_key "KEY_${char}" ;;
            ' ') send_key KEY_SPACE ;;
            '+') send_key KEY_LEFTSHIFT KEY_EQUAL ;;
            '/') send_key KEY_SLASH ;;
            '=') send_key KEY_EQUAL ;;
            '-') send_key KEY_MINUS ;;
            *) die "cannot type this password character" ;;
        esac
        sleep 0.06
    done
}

click_at() {
    local x="$1" y="$2" width="$3" height="$4" ax ay
    ax=$((x * 32767 / width))
    ay=$((y * 32767 / height))
    sudo virsh qemu-monitor-command "$GOLDEN_NAME" \
        "{\"execute\":\"input-send-event\",\"arguments\":{\"events\":[{\"type\":\"abs\",\"data\":{\"axis\":\"x\",\"value\":${ax}}},{\"type\":\"abs\",\"data\":{\"axis\":\"y\",\"value\":${ay}}}]}}" \
        >/dev/null
    sleep 0.15
    sudo virsh qemu-monitor-command "$GOLDEN_NAME" \
        '{"execute":"input-send-event","arguments":{"events":[{"type":"btn","data":{"down":true,"button":"left"}}]}}' \
        >/dev/null
    sleep 0.12
    sudo virsh qemu-monitor-command "$GOLDEN_NAME" \
        '{"execute":"input-send-event","arguments":{"events":[{"type":"btn","data":{"down":false,"button":"left"}}]}}' \
        >/dev/null
}

wait_for_desktop() {
    local i size
    for i in $(seq 1 48); do
        take_screenshot
        size="$(stat -c %s "$SHOT" 2>/dev/null || echo 0)"
        if [[ "$size" -gt 50000 ]]; then
            return 0
        fi
        sleep 5
    done
    die "the live desktop did not appear"
}

# The red word "delete" sits on a fixed offset from the erase radio.
erase_click_point() {
    python3 - "$SHOT" <<'PY'
import struct
import sys
import zlib

def load_png(path):
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit("not a png")
    pos = 8
    width = height = None
    idat = b""
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width, height = struct.unpack(">II", chunk[:8])
            if chunk[8] != 8 or chunk[9] != 2:
                raise SystemExit("png is not 8-bit rgb")
        elif kind == b"IDAT":
            idat += chunk
        elif kind == b"IEND":
            break
    raw = zlib.decompress(idat)
    stride = width * 3
    rows = []
    index = 0
    prev = bytearray(stride)

    def paeth(left, up, up_left):
        estimate = left + up - up_left
        if abs(estimate - left) <= abs(estimate - up) and abs(estimate - left) <= abs(estimate - up_left):
            return left
        if abs(estimate - up) <= abs(estimate - up_left):
            return up
        return up_left

    for _y in range(height):
        filt = raw[index]
        index += 1
        row = bytearray(raw[index:index + stride])
        index += stride
        if filt == 1:
            for x in range(stride):
                left = row[x - 3] if x >= 3 else 0
                row[x] = (row[x] + left) & 255
        elif filt == 2:
            for x in range(stride):
                row[x] = (row[x] + prev[x]) & 255
        elif filt == 3:
            for x in range(stride):
                left = row[x - 3] if x >= 3 else 0
                row[x] = (row[x] + ((left + prev[x]) // 2)) & 255
        elif filt == 4:
            for x in range(stride):
                left = row[x - 3] if x >= 3 else 0
                up = prev[x]
                up_left = prev[x - 3] if x >= 3 else 0
                row[x] = (row[x] + paeth(left, up, up_left)) & 255
        elif filt != 0:
            raise SystemExit(f"unknown png filter {filt}")
        prev = bytes(row)
        rows.append(row)
    return width, height, rows

width, height, rows = load_png(sys.argv[1])
xs = []
ys = []
for y in range(int(height * 0.15), int(height * 0.5)):
    row = rows[y]
    for x in range(int(width * 0.2), width):
        red, green, blue = row[x * 3:x * 3 + 3]
        if red > 150 and green < 90 and blue < 90 and red > green + 60:
            xs.append(x)
            ys.append(y)
if len(xs) < 40:
    raise SystemExit("erase-disk label was not found")
click_x = min(xs) - int(41 * width / 1280)
click_y = min(ys) - int(4 * height / 800)
print(f"{click_x} {click_y} {width} {height}")
PY
}

select_erase_disk() {
    local point x y width height
    take_screenshot
    point="$(erase_click_point)" || die "could not find the erase-disk choice"
    read -r x y width height <<<"$point"
    click_at "$x" "$y" "$width" "$height"
}

fill_user_page() {
    local pass
    pass="$(tr -d '\n' <"$PASS_FILE")"
    [[ -n "$pass" ]] || die "password file is empty"
    send_text dragon
    sleep 0.3
    send_key KEY_TAB
    sleep 0.15
    send_key KEY_TAB
    sleep 0.15
    send_key KEY_LEFTCTRL KEY_A
    sleep 0.15
    send_text testbed
    send_key KEY_TAB
    sleep 0.15
    send_text "$pass"
    send_key KEY_TAB
    sleep 0.15
    send_text "$pass"
    send_key KEY_TAB
    sleep 0.1
    send_key KEY_TAB
    sleep 0.1
    send_key KEY_SPACE
}

drive_calamares() {
    wait_for_desktop
    send_key KEY_LEFTALT KEY_F2
    sleep 0.8
    send_text calamares
    sleep 0.4
    send_key KEY_ENTER
    sleep 4
    send_key KEY_LEFTALT KEY_N
    sleep 0.8
    send_text am
    sleep 0.2
    send_key KEY_TAB
    sleep 0.25
    send_text chic
    sleep 0.3
    send_key KEY_LEFTALT KEY_N
    sleep 0.8
    send_key KEY_LEFTALT KEY_N
    sleep 1
    select_erase_disk
    sleep 0.6
    send_key KEY_LEFTALT KEY_N
    sleep 0.8
    fill_user_page
    sleep 0.4
    send_key KEY_LEFTALT KEY_I
    sleep 1
    send_key KEY_ENTER
    wait_for_install_reboot
}

# The install slide is a dark panel. The finish page is a light page
# with an unchecked "Restart now" box near (695, 544) at 1280x800.
screen_center() {
    python3 - "$SHOT" <<'PY'
import struct
import sys
import zlib

data = open(sys.argv[1], "rb").read()
pos = 8
width = height = None
idat = b""
while pos < len(data):
    length = struct.unpack(">I", data[pos:pos + 4])[0]
    kind = data[pos + 4:pos + 8]
    chunk = data[pos + 8:pos + 8 + length]
    pos += 12 + length
    if kind == b"IHDR":
        width, height = struct.unpack(">II", chunk[:8])
    elif kind == b"IDAT":
        idat += chunk
    elif kind == b"IEND":
        break
raw = zlib.decompress(idat)
stride = width * 3
index = 0
prev = bytearray(stride)

def paeth(left, up, up_left):
    estimate = left + up - up_left
    if abs(estimate - left) <= abs(estimate - up) and abs(estimate - left) <= abs(estimate - up_left):
        return left
    if abs(estimate - up) <= abs(estimate - up_left):
        return up
    return up_left

target_y = height // 2
row = None
for y in range(height):
    filt = raw[index]
    index += 1
    buf = bytearray(raw[index:index + stride])
    index += stride
    if filt == 1:
        for x in range(stride):
            left = buf[x - 3] if x >= 3 else 0
            buf[x] = (buf[x] + left) & 255
    elif filt == 2:
        for x in range(stride):
            buf[x] = (buf[x] + prev[x]) & 255
    elif filt == 3:
        for x in range(stride):
            left = buf[x - 3] if x >= 3 else 0
            buf[x] = (buf[x] + ((left + prev[x]) // 2)) & 255
    elif filt == 4:
        for x in range(stride):
            left = buf[x - 3] if x >= 3 else 0
            buf[x] = (buf[x] + paeth(left, prev[x], prev[x - 3] if x >= 3 else 0)) & 255
    prev = bytes(buf)
    if y == target_y:
        row = buf
        break
red, green, blue = row[(width // 2) * 3:(width // 2) * 3 + 3]
light = "yes" if red > 200 and green > 200 and blue > 200 else "no"
print(f"{light} {width} {height}")
PY
}

confirm_restart() {
    local light width height
    take_screenshot
    read -r light width height <<<"$(screen_center)"
    [[ "$light" == "yes" ]] || return 1
    click_at $((695 * width / 1280)) $((544 * height / 800)) "$width" "$height"
    sleep 0.4
    send_key KEY_LEFTALT KEY_D
}

wait_for_install_reboot() {
    local i state light width height saw_install=0 restarted=0
    for i in $(seq 1 80); do
        state="$(domain_state "$GOLDEN_NAME")"
        if [[ "$state" == "shut off" ]]; then
            boot_installed_disk
            wait_for_guest_ssh
            return 0
        fi
        take_screenshot || true
        read -r light width height <<<"$(screen_center)" || true
        if [[ "$light" != "yes" ]]; then
            saw_install=1
        elif [[ "$saw_install" == "1" && "$restarted" != "1" ]]; then
            confirm_restart || true
            restarted=1
        fi
        sleep 10
    done
    die "install did not reboot the golden domain"
}

boot_installed_disk() {
    sudo virsh change-media "$GOLDEN_NAME" sda --eject >/dev/null 2>&1 || true
    sudo virt-xml "$GOLDEN_NAME" --edit --boot hd >/dev/null
    sudo virsh start "$GOLDEN_NAME" >/dev/null
}

wait_for_guest_ssh() {
    local i ip
    for i in $(seq 1 36); do
        ip="$(guest_ip "$GOLDEN_NAME")"
        if [[ -n "$ip" ]] && ssh_guest "$GOLDEN_NAME" true; then
            return 0
        fi
        sleep 5
    done
    die "installed system did not accept ssh"
}

write_repo_mount() {
    {
        cat "$PASS_FILE"
        cat <<'EOF'
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
    } | ssh_guest "$GOLDEN_NAME" \
        "sudo -S tee /etc/systemd/system/dotfiles-repo.service >/dev/null"
    ssh_guest "$GOLDEN_NAME" "sudo -S systemctl enable dotfiles-repo.service" \
        <"$PASS_FILE"
}

# sddm swallows the ACPI button, and systemctl poweroff can sit on
# polkit. Ask the guest to power off, then cut power if it is still up.
power_off_domain() {
    local name="$1"
    local i state
    state="$(domain_state "$name")"
    if [[ "$state" == "shut off" || "$state" == "absent" ]]; then
        return 0
    fi
    ssh_guest "$name" "sudo -S systemctl poweroff --no-block" \
        <"$PASS_FILE" || true
    for i in $(seq 1 15); do
        state="$(domain_state "$name")"
        [[ "$state" == "shut off" || "$state" == "absent" ]] && break
        sleep 3
    done
    state="$(domain_state "$name")"
    if [[ "$state" != "shut off" && "$state" != "absent" ]]; then
        sudo virsh destroy "$name" >/dev/null
    fi
    wait_shutoff "$name"
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
    power_off_domain "$GOLDEN_NAME"
    rotate_backup "$GOLDEN_DISK" "$BACKUP_DIR"
}

cmd_backup() {
    local state
    state="$(domain_state "$GOLDEN_NAME")"
    golden_is_idle "$state" || die "shut the golden domain down before backup (state: ${state:-empty})"
    if [[ ! -f "$GOLDEN_DISK" ]] && ! sudo test -f "$GOLDEN_DISK"; then
        die "missing ${GOLDEN_DISK}"
    fi
    rotate_backup "$GOLDEN_DISK" "$BACKUP_DIR"
}

clone_filesystem_args() {
    printf '%s' "type=mount,driver.type=virtiofs,source=${REPO},target=dotfiles,accessmode=passthrough"
}

cmd_up() {
    local state clone_state
    require_host
    state="$(domain_state "$GOLDEN_NAME")"
    if ! up_allowed "$state" "${BACKUP_DIR}/golden.qcow2"; then
        die "refusing to boot the clone (golden state: ${state:-empty})"
    fi
    if [[ ! -f "$GOLDEN_DISK" ]] && ! sudo test -f "$GOLDEN_DISK"; then
        die "missing ${GOLDEN_DISK}"
    fi
    if [[ ! -e "$CLONE_DISK" ]] && ! sudo test -e "$CLONE_DISK"; then
        sudo qemu-img create -f qcow2 -b "$GOLDEN_DISK" -F qcow2 "$CLONE_DISK"
    fi
    clone_state="$(domain_state "$CLONE_NAME")"
    case "$clone_state" in
        absent)
            sudo virt-install \
                --name "$CLONE_NAME" \
                --memory 8192 \
                --vcpus 4 \
                --cpu host-passthrough \
                --disk "path=${CLONE_DISK},bus=virtio" \
                --import \
                --os-variant linux2022 \
                --graphics vnc,listen=127.0.0.1 \
                --video virtio \
                --sound none \
                --boot uefi \
                --network network=default \
                --memorybacking source.type=memfd,access.mode=shared \
                --filesystem "$(clone_filesystem_args)" \
                --noautoconsole \
                --wait 0
            ;;
        "shut off")
            sudo virsh start "$CLONE_NAME"
            ;;
        running) ;;
        *)
            die "clone domain is ${clone_state}"
            ;;
    esac
}

cmd_ssh() {
    ensure_key
    ssh_guest "$CLONE_NAME" "$@"
}

cmd_down() {
    power_off_domain "$CLONE_NAME"
}

cmd_destroy_clone() {
    local state
    state="$(domain_state "$CLONE_NAME")"
    if [[ "$state" == "unknown" ]]; then
        die "cannot read clone domain state"
    fi
    if [[ "$state" != "absent" ]]; then
        sudo virsh destroy "$CLONE_NAME" >/dev/null 2>&1 || true
        sudo virsh undefine "$CLONE_NAME" --nvram >/dev/null 2>&1 || \
            sudo virsh undefine "$CLONE_NAME" >/dev/null 2>&1 || true
    fi
    if [[ -e "$CLONE_DISK" ]] || sudo test -e "$CLONE_DISK"; then
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
