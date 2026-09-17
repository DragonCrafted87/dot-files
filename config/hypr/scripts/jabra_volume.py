"""Apply Jabra Speak 710 buttons only to the Jabra PipeWire sink."""

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
EV_MSC = 4
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


def handle_event(event, debug=False):
    _sec, _usec, ev_type, code, value = event
    if debug and ev_type != EV_SYN:
        print(f"event type={ev_type} code={code} value={value}", flush=True)
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


def open_devices():
    opened = {}
    for path, name in jabra_event_nodes():
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        except OSError as exc:
            print(f"{path}: {exc}", file=sys.stderr)
            continue
        grabbed = grab(fd)
        print(f"watching {path} ({name}) grab={'yes' if grabbed else 'no'}", flush=True)
        opened[fd] = path
    return opened


def watch(debug=False):
    devices = {}
    known = set()
    print("watching Jabra Speak buttons for the Jabra sink", flush=True)
    while True:
        current = {path for path, _name in jabra_event_nodes()}
        if current != known:
            for fd in list(devices):
                os.close(fd)
            devices = open_devices()
            known = set(devices.values())
        if not devices:
            time.sleep(1.0)
            continue
        ready, _, _ = select.select(list(devices), [], [], 1.0)
        for fd in ready:
            try:
                blob = os.read(fd, EVENT_SIZE * 16)
            except OSError:
                known = set()
                continue
            if debug and blob:
                print(f"raw {len(blob)} bytes {blob[:EVENT_SIZE].hex()}", flush=True)
            for offset in range(0, len(blob) // EVENT_SIZE * EVENT_SIZE, EVENT_SIZE):
                handle_event(
                    struct.unpack(EVENT_FORMAT, blob[offset : offset + EVENT_SIZE]),
                    debug=debug,
                )


def print_status():
    nodes = jabra_event_nodes()
    sink = jabra_sink_id()
    print(f"jabra_sink={sink or 'none'}")
    if not nodes:
        print("jabra_input=none")
        return 0
    for path, name in nodes:
        print(f"jabra_input={path} {name}")
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
