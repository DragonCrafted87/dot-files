"""Apply Jabra Speak 710 buttons only to the Jabra PipeWire sink."""

import glob
import json
import os
import select
import struct
import subprocess
import sys
import time

JABRA_VENDOR = "0b0e"
EVENT_FORMAT = "llHHi"
EVENT_SIZE = struct.calcsize(EVENT_FORMAT)
EV_KEY = 1
KEY_MUTE = 113
KEY_VOLUMEDOWN = 114
KEY_VOLUMEUP = 115
EVIOCGRAB = 0x40044590


def usage():
    print("Usage: jabra_volume.py raise|lower|mute|watch|status", file=sys.stderr)
    raise SystemExit(1)


def read_text(path):
    try:
        with open(path, encoding="utf-8", errors="ignore") as handle:
            return handle.read().strip()
    except OSError:
        return ""


def jabra_event_nodes():
    nodes = []
    for name_path in glob.glob("/sys/class/input/event*/device/name"):
        event_dir = os.path.dirname(os.path.dirname(name_path))
        event_name = os.path.basename(event_dir)
        vendor = read_text(os.path.join(os.path.dirname(name_path), "id", "vendor")).lower()
        product_name = read_text(name_path).lower()
        if vendor.lstrip("0x") != JABRA_VENDOR and "jabra" not in product_name:
            continue
        nodes.append((f"/dev/input/{event_name}", read_text(name_path)))
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


def wpctl_jabra(*args):
    sink = jabra_sink_id()
    if sink is None:
        print("no Jabra sink", file=sys.stderr)
        return 1
    subprocess.check_call(["wpctl", *args, sink, *args[3:] if False else []])
    return 0


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
    return 0


def grab(fd):
    try:
        import fcntl

        fcntl.ioctl(fd, EVIOCGRAB, 1)
        return True
    except OSError:
        return False


def handle_event(event):
    _sec, _usec, ev_type, code, value = event
    if ev_type != EV_KEY or value != 1:
        return
    if code == KEY_VOLUMEUP:
        apply("raise")
    elif code == KEY_VOLUMEDOWN:
        apply("lower")
    elif code == KEY_MUTE:
        apply("mute")


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


def watch():
    devices = {}
    last_scan = 0.0
    print("watching Jabra Speak buttons for the Jabra sink", flush=True)
    while True:
        now = time.monotonic()
        if now - last_scan >= 2.0:
            for fd in list(devices):
                os.close(fd)
            devices = open_devices()
            last_scan = now
        if not devices:
            time.sleep(1.0)
            continue
        ready, _, _ = select.select(list(devices), [], [], 1.0)
        for fd in ready:
            try:
                blob = os.read(fd, EVENT_SIZE * 8)
            except OSError:
                continue
            for offset in range(0, len(blob) // EVENT_SIZE * EVENT_SIZE, EVENT_SIZE):
                handle_event(struct.unpack(EVENT_FORMAT, blob[offset : offset + EVENT_SIZE]))


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
    if command == "watch":
        watch()
        return 0
    usage()
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
