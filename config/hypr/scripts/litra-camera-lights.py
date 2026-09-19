# pylint: disable=invalid-name
"""Turn Logitech Litra Glow lamps on while the Insta360 Link is streaming."""

import glob
import os
import sys
import time
from pathlib import Path

LITRA_VENDOR = 0x046D
LITRA_PRODUCT = 0xC900
CAMERA_VENDOR = 0x2E1A
REPORT_LEN = 20
POLL_SECONDS = 0.4
DEBOUNCE_SECONDS = 1.5
STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "hypr"
HOLD_FILE = STATE_DIR / "litra-hold-on"


def usage():
    print(
        "Usage: litra-camera-lights.py on|off|toggle|status|watch [--hold]",
        file=sys.stderr,
    )
    raise SystemExit(1)


def hold_enabled() -> bool:
    return HOLD_FILE.is_file()


def set_hold(enabled: bool) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    if enabled:
        HOLD_FILE.write_text("1\n", encoding="utf-8")
    elif HOLD_FILE.exists():
        HOLD_FILE.unlink()


def read_text(path):
    try:
        with open(path, encoding="utf-8", errors="ignore") as handle:
            return handle.read().strip()
    except OSError:
        return ""


def hid_id_from_uevent(path):
    for line in read_text(path).splitlines():
        if line.startswith("HID_ID="):
            parts = line.split("=", 1)[1].split(":")
            if len(parts) >= 3:
                try:
                    return int(parts[1], 16), int(parts[2], 16)
                except ValueError:
                    return None
    return None


def litra_hidraw_nodes():
    nodes = []
    for uevent in glob.glob("/sys/class/hidraw/hidraw*/device/uevent"):
        hid_id = hid_id_from_uevent(uevent)
        if hid_id != (LITRA_VENDOR, LITRA_PRODUCT):
            continue
        name = os.path.basename(os.path.dirname(os.path.dirname(uevent)))
        nodes.append(f"/dev/{name}")
    return sorted(set(nodes))


def litra_report(turn_on):
    payload = bytearray(REPORT_LEN)
    payload[0] = 0x11
    payload[1] = 0xFF
    payload[2] = 0x04
    payload[3] = 0x1C
    payload[4] = 0x01 if turn_on else 0x00
    return bytes(payload)


def send_litra(turn_on):
    nodes = litra_hidraw_nodes()
    if not nodes:
        print("no Litra Glow hidraw nodes found", file=sys.stderr)
        return 1
    report = litra_report(turn_on)
    failed = 0
    for node in nodes:
        try:
            with open(node, "wb", buffering=0) as handle:
                handle.write(report)
            print(f"{'on' if turn_on else 'off'} {node}")
        except OSError as exc:
            print(f"{node}: {exc}", file=sys.stderr)
            failed += 1
    return 1 if failed else 0


def usb_ids_for_video(sys_path):
    current = os.path.realpath(sys_path)
    for _ in range(12):
        vendor = read_text(os.path.join(current, "idVendor"))
        product = read_text(os.path.join(current, "idProduct"))
        if vendor and product:
            try:
                return int(vendor, 16), int(product, 16)
            except ValueError:
                return None
        parent = os.path.dirname(current)
        if parent == current:
            break
        current = parent
    return None


def insta360_video_nodes():
    nodes = []
    for name_path in glob.glob("/sys/class/video4linux/video*/name"):
        sys_dir = os.path.dirname(name_path)
        device_dir = os.path.join(sys_dir, "device")
        usb_ids = usb_ids_for_video(device_dir)
        if usb_ids is None or usb_ids[0] != CAMERA_VENDOR:
            name = read_text(name_path).lower()
            if "insta360" not in name and "link" not in name:
                continue
        nodes.append("/dev/" + os.path.basename(sys_dir))
    return sorted(set(nodes))


def open_video_nodes():
    wanted = set(insta360_video_nodes())
    if not wanted:
        return set()
    opened = set()
    self_pid = str(os.getpid())
    for fd_dir in glob.glob("/proc/[0-9]*/fd"):
        pid = fd_dir.split("/")[2]
        if pid == self_pid:
            continue
        try:
            for fd_path in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd_path))
                except OSError:
                    continue
                if target in wanted:
                    opened.add(target)
        except OSError:
            continue
    return opened


def camera_is_live():
    return bool(open_video_nodes())


def print_status():
    lights = litra_hidraw_nodes()
    cameras = insta360_video_nodes()
    opened = open_video_nodes()
    print(f"litra_nodes={' '.join(lights) if lights else 'none'}")
    print(f"camera_nodes={' '.join(cameras) if cameras else 'none'}")
    print(f"camera_open={' '.join(sorted(opened)) if opened else 'none'}")
    print(f"camera_live={'yes' if opened else 'no'}")
    print(f"hold_on={'yes' if hold_enabled() else 'no'}")
    return 0


def watch():
    desired = None
    pending = None
    pending_since = 0.0
    print("watching Insta360 Link for Litra Glow on/off", flush=True)
    while True:
        live = camera_is_live()
        held = hold_enabled()
        # Manual hold keeps lamps on even when the camera is idle. Camera
        # start still forces on so a hold + stream cannot leave them dark.
        target = True if (live or held) else False
        now = time.monotonic()
        if target != pending:
            pending = target
            pending_since = now
        elif pending is not None and now - pending_since >= DEBOUNCE_SECONDS:
            if pending != desired:
                desired = pending
                send_litra(desired)
        time.sleep(POLL_SECONDS)


def main(argv):
    args = [a for a in argv[1:] if a != "--hold"]
    hold_flag = "--hold" in argv[1:]
    command = args[0] if args else "watch"
    if command in {"-h", "--help", "help"}:
        usage()
    if command == "on":
        set_hold(True)
        return send_litra(True)
    if command == "off":
        set_hold(False)
        return send_litra(False)
    if command == "toggle":
        if hold_enabled() and not hold_flag:
            set_hold(False)
            return send_litra(False)
        set_hold(True)
        return send_litra(True)
    if command == "status":
        return print_status()
    if command == "watch":
        watch()
        return 0
    usage()
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
