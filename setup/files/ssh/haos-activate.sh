#!/bin/sh
# Record the tty1 mask on the boot cmdline, then start the supervisor
# for this boot. /mnt/boot/cmdline.txt is the vfat line grub appends.
# systemd.mask applies for that boot and does not replace default.target.

set -eu

rewrite_cmdline() {
    old="$1"
    old="$(printf '%s' "$old" | tr -d '\r')"
    new=""
    rest="$old"
    while [ -n "$rest" ]; do
        word="${rest%% *}"
        case "$rest" in
            *" "*)
                rest="${rest#* }"
                ;;
            *)
                rest=""
                ;;
        esac
        case "$word" in
            "" | systemd.mask=ha-cli@tty1.service | systemd.mask=getty@tty1.service)
                ;;
            *)
                new="${new}${new:+ }${word}"
                ;;
        esac
    done
    new="${new}${new:+ }systemd.mask=ha-cli@tty1.service systemd.mask=getty@tty1.service"
    printf '%s\n' "$new"
}

if [ "${1:-}" = "--rewrite-cmdline" ]; then
    rewrite_cmdline "${2:-}"
    exit 0
fi

file="/mnt/boot/cmdline.txt"
test -f "$file"
old="$(tr -d '\r' <"$file")"
had=0
case " $old " in
    *" console=tty0 "*)
        had=1
        ;;
esac
new="$(rewrite_cmdline "$old")"
if [ "$had" -eq 1 ]; then
    case " $new " in
        *" console=tty0 "*)
            ;;
        *)
            printf 'refusing to drop console=tty0\n' >&2
            exit 1
            ;;
    esac
fi
tmp="$(mktemp)"
printf '%s\n' "$new" >"$tmp"
cat "$tmp" >"$file"
rm -f "$tmp"

udevadm control --reload-rules

if systemctl is-active -q haos-dot-files.service; then
    systemctl stop haos-dot-files.service
fi
systemctl reset-failed haos-dot-files.service >/dev/null 2>&1 || true
systemd-run --unit=haos-dot-files.service --collect \
    --description='Home Assistant OS dot-files' \
    /mnt/overlay/dot-files/haos-supervise.sh

i=0
while [ "$i" -lt 20 ]; do
    if [ -s /mnt/overlay/dot-files/haos-console-lock.pid ]; then
        pid="$(cat /mnt/overlay/dot-files/haos-console-lock.pid)"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            exit 0
        fi
    fi
    i=$((i + 1))
    sleep 1
done
printf 'console lock did not start\n' >&2
exit 1
