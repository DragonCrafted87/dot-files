"""Apply Jabra Speak 710 controls only to the Jabra PipeWire sink."""

import fcntl
import glob
import json
import os
import select
import struct
import subprocess
import sys
import time

JABRA_VENDOR = 0x0B0E
EVENT_FORMAT = "llHHi"
EVENT_SIZE = struct.calcsize(EVENT_FORMAT)
EV_SYN = 0
EV_KEY = 1
EV_REL = 2
EV_ABS = 3
KEY_MUTE = 113
KEY_VOLUMEDOWN = 114
KEY_VOLUMEUP = 115
REL_HWHEEL = 6
REL_DIAL = 7
REL_WHEEL = 8
REL_WHEEL_HI_RES = 11
REL_HWHEEL_HI_RES = 12
ABS_WHEEL = 8
ABS_MISC = 0x28
EVIOCGRAB = 0x40044590
HIDIOCGRAWINFO = 0x80084803


def usage():
    print("Usage: jabra_volume.py raise|lower|mute|watch|dump|status", file=sys.stderr)
    raise SystemExit(1)


def read_text(path):
    try:
        with open(path, encoding="utf-8", errors="ignore") as handle:
            return handle.read().strip()
    except OSError:
        return ""


def parse_hex(value):
    try:
        return int(value, 16)
    except ValueError:
        return None


def jabra_event_nodes():
    nodes = []
    for name_path in glob.glob("/sys/class/input/event*/device/name"):
        event_dir = os.path.dirname(os.path.dirname(name_path))
        event_name = os.path.basename(event_dir)
        vendor = parse_hex(read_text(os.path.join(os.path.dirname(name_path), "id", "vendor")))
        product_name = read_text(name_path)
        if vendor != JABRA_VENDOR and "jabra" not in product_name.lower():
            continue
        nodes.append((f"/dev/input/{event_name}", product_name))
    return nodes


def hid_ids(uevent):
    vendor = None
    product = None
    for line in uevent.splitlines():
        if not line.startswith("HID_ID="):
            continue
        parts = line.split("=", 1)[1].split(":")
        if len(parts) >= 3:
            vendor = parse_hex(parts[1])
            product = parse_hex(parts[2])
    return vendor, product


def jabra_hidraw_nodes():
    nodes = []
    for uevent_path in glob.glob("/sys/class/hidraw/hidraw*/device/uevent"):
        hidraw = os.path.basename(os.path.dirname(os.path.dirname(uevent_path)))
        uevent = read_text(uevent_path)
        vendor, product = hid_ids(uevent)
        name = ""
        for line in uevent.splitlines():
            if line.startswith("HID_NAME="):
                name = line.split("=", 1)[1]
        if vendor != JABRA_VENDOR and "jabra" not in name.lower():
            continue
        nodes.append((f"/dev/{hidraw}", name or f"{vendor:04x}:{product:04x}" if vendor else hidraw))
    return nodes


def pw_dump():
    try:
        data = json.loads(subprocess.check_output(["pw-dump"], text=True))
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError):
        return []
    return data if isinstance(data, list) else []


def node_props(obj):
    info = obj.get("info") or {}
    props = info.get("props") or {}
    return props if isinstance(props, dict) else {}


def jabra_sink_id():
    for obj in pw_dump():
        if obj.get("type") != "PipeWire:Interface:Node":
            continue
        props = node_props(obj)
        if props.get("media.class") != "Audio/Sink":
            continue
        blob = " ".join(
            str(props.get(key, ""))
            for key in ("node.description", "node.nick", "node.name", "device.description")
        ).lower()
        if "jabra" not in blob:
            continue
        ident = obj.get("id")
        if ident is None:
            ident = props.get("object.id")
        if ident is not None:
            return str(ident)
    return None


def apply(action):
    sink = jabra_sink_id()
    if sink is None:
        print("no Jabra sink", file=sys.stderr)
        return 1
    if action == "raise":
        subprocess.check_call(["wpctl", "set-volume", "-l", "1", sink, "5%+"])
    elif action == "lower":
        subprocess.check_call(["wpctl", "set-volume", sink, "5%-"])
    elif action == "mute":
        subprocess.check_call(["wpctl", "set-mute", sink, "toggle"])
    else:
        return 1
    print(f"jabra {action} sink={sink}", flush=True)
    return 0


def grab(fd):
    try:
        fcntl.ioctl(fd, EVIOCGRAB, 1)
        return True
    except OSError:
        return False


def handle_evdev(event, debug=False):
    _sec, _usec, ev_type, code, value = event
    if debug and ev_type != EV_SYN:
        print(f"evdev type={ev_type} code={code} value={value}", flush=True)
    if ev_type == EV_KEY and value in {1, 2}:
        if code == KEY_VOLUMEUP:
            apply("raise")
        elif code == KEY_VOLUMEDOWN:
            apply("lower")
        elif code == KEY_MUTE:
            apply("mute")
        return
    if ev_type == EV_REL and value:
        if code in {REL_WHEEL, REL_DIAL, REL_HWHEEL, REL_WHEEL_HI_RES, REL_HWHEEL_HI_RES}:
            apply("raise" if value > 0 else "lower")
        return
    if ev_type == EV_ABS and code in {ABS_WHEEL, ABS_MISC}:
        if value > 0:
            apply("raise")
        elif value < 0:
            apply("lower")


def decode_hid(report, previous, debug=False):
    if debug:
        print(f"hidraw {report.hex()}", flush=True)
    if not report:
        return previous
    current = report[1] if len(report) > 1 else report[0]
    prev = previous[1] if previous and len(previous) > 1 else (previous[0] if previous else 0)
    risen = current & ~prev
    if risen & 0x02:
        apply("raise")
    elif risen & 0x01:
        apply("lower")
    elif risen & 0x04:
        apply("mute")
    elif previous and report != previous and not risen:
        # Rotary reports often change a later byte instead of the consumer bits.
        if len(report) >= 3 and previous and len(previous) >= 3 and report[2] != previous[2]:
            delta = report[2] - previous[2]
            if delta > 128:
                delta -= 256
            elif delta < -128:
                delta += 256
            if delta:
                apply("raise" if delta > 0 else "lower")
    return report


def open_watchers():
    opened = {}
    for path, name in jabra_event_nodes():
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        except OSError as exc:
            print(f"{path}: {exc}", file=sys.stderr)
            continue
        grabbed = grab(fd)
        print(f"evdev {path} ({name}) grab={'yes' if grabbed else 'no'}", flush=True)
        opened[fd] = ("evdev", path)
    for path, name in jabra_hidraw_nodes():
        try:
            fd = os.open(path, os.O_RDWR | os.O_NONBLOCK)
        except OSError:
            try:
                fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
            except OSError as exc:
                print(f"{path}: {exc}", file=sys.stderr)
                continue
        print(f"hidraw {path} ({name})", flush=True)
        opened[fd] = ("hidraw", path)
    return opened


def watch(debug=False):
    devices = {}
    last_hid = {}
    known = None
    print("watching Jabra Speak HID and evdev for the Jabra sink", flush=True)
    while True:
        signature = tuple(jabra_event_nodes() + jabra_hidraw_nodes())
        if signature != known:
            for fd in list(devices):
                os.close(fd)
            devices = open_watchers()
            last_hid = {}
            known = signature
        if not devices:
            time.sleep(1.0)
            continue
        ready, _, _ = select.select(list(devices), [], [], 1.0)
        for fd in ready:
            kind, path = devices[fd]
            try:
                blob = os.read(fd, 64 if kind == "hidraw" else EVENT_SIZE * 16)
            except OSError:
                known = None
                continue
            if not blob:
                continue
            if kind == "evdev":
                for offset in range(0, len(blob) // EVENT_SIZE * EVENT_SIZE, EVENT_SIZE):
                    handle_evdev(
                        struct.unpack(EVENT_FORMAT, blob[offset : offset + EVENT_SIZE]),
                        debug=debug,
                    )
                continue
            last_hid[path] = decode_hid(blob, last_hid.get(path), debug=debug)


def print_status():
    sink = jabra_sink_id()
    print(f"jabra_sink={sink or 'none'}")
    nodes = jabra_event_nodes()
    hid = jabra_hidraw_nodes()
    if not nodes:
        print("jabra_input=none")
    for path, name in nodes:
        print(f"jabra_input={path} {name}")
    if not hid:
        print("jabra_hidraw=none")
    for path, name in hid:
        print(f"jabra_hidraw={path} {name}")
    return 0


def main(argv):
    command = argv[1] if len(argv) > 1 else "watch"
    if command in {"-h", "--help", "help"}:
        usage()
    if command in {"raise", "lower", "mute"}:
        return apply(command)
    if command == "status":
        return print_status()
    if command == "dump":
        watch(debug=True)
        return 0
    if command == "watch":
        watch(debug=False)
        return 0
    usage()
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
