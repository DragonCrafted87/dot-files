#!/usr/bin/env bash
# Status / pairing helper. xpadneo and xone are kernel modules, not apps.
set -euo pipefail

cmd="${1:-status}"

status() {
    printf 'kernel:     %s\n' "$(uname -r)"
    printf 'dkms:\n'
    dkms status 2>/dev/null | grep -Ei 'xone|xpadneo|hid-xpadneo' | sed 's/^/  /' || printf '  none\n'
    printf 'modules:\n'
    lsmod | awk '/xone|hid_xpadneo|xpad /{print "  "$0}' || printf '  none loaded\n'
    printf 'firmware:   '
    if [[ -f /lib/firmware/xow_dongle.bin || -f /usr/lib/firmware/xow_dongle.bin ]]; then
        echo present
    else
        echo MISSING
    fi
    printf 'usb dongle:\n'
    lsusb | grep -Ei '045e:02e6|045e:02fe|XBOX ACC|Xbox Wireless' | sed 's/^/  /' || printf '  not plugged in\n'
    printf 'input:\n'
    grep -A2 -iE 'Xbox|xone|xpadneo' /proc/bus/input/devices | sed 's/^/  /' || printf '  no xbox node\n'
    printf 'bluetooth:\n'
    if command -v bluetoothctl >/dev/null; then
        bluetoothctl devices 2>/dev/null | grep -iE 'xbox|elite' | sed 's/^/  /' || printf '  no xbox BT device\n'
    else
        printf '  bluetoothctl missing\n'
    fi
}

usage() {
    cat <<'EOF'
xbox-pad — Xbox Elite helper (xone dongle + xpadneo Bluetooth)

  xbox-pad              status
  xbox-pad status
  xbox-pad pair-dongle  remind pairing steps
  xbox-pad pair-bt      bluetoothctl scan reminder
  xbox-pad configure    xpadneo configure.sh (Bluetooth only)
  xbox-pad rebuild      dkms install both drivers for this kernel

xpadneo is hid_xpadneo. There is no desktop launcher. Pair in blueman
or bluetoothctl, then the module attaches. Configure from:
  sudo ~/src/xpadneo/configure.sh

Dongle path uses xone, not xpadneo. Do not pair the same pad on both.
EOF
}

case "$cmd" in
    -h | --help | help) usage ;;
    status | "") status ;;
    pair-dongle)
        cat <<'EOF'
1. Unplug Bluetooth for this pad (bluetoothctl disconnect/remove).
2. Plug the slim adapter into a rear USB-A port.
3. Hold the button on the dongle until it blinks.
4. Hold the pair button on the Elite until the Xbox button blinks.
5. xbox-pad status  — expect xone_dongle loaded and an Xbox input node.
EOF
        ;;
    pair-bt)
        cat <<'EOF'
Hold the Elite pair button until it blinks.
Then:
  bluetoothctl
  power on
  scan on
  pair XX:XX:XX:XX:XX:XX
  trust XX:XX:XX:XX:XX:XX
  connect XX:XX:XX:XX:XX:XX

lsmod should show hid_xpadneo after it connects. Profiles set in the
Windows Xbox Accessories app carry over. Default profile (no LED)
exposes paddles as extra buttons.
EOF
        ;;
    configure)
        script="${XPADNEO_DIR:-$HOME/src/xpadneo}/configure.sh"
        [[ -x "$script" ]] || {
            echo "missing $script" >&2
            exit 1
        }
        exec sudo "$script"
        ;;
    rebuild)
        sudo dkms autoinstall
        echo "dkms status:"
        dkms status | grep -Ei 'xone|xpadneo' || true
        sudo modprobe xone-dongle 2>/dev/null || true
        sudo modprobe hid-xpadneo 2>/dev/null || true
        status
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
