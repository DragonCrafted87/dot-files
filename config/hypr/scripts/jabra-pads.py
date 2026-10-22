# pylint: disable=invalid-name
"""Point the Jabra Speak 710 pads at the Jabra, not the soundbar.

Volume pads are consumer keys on the Speak 710 event node. This process
grabs that node so Hyprland does not also step the default sink. The mute
pad is telephony report id 2, bit 0x04. The descriptor marks that bit
constant, so it never becomes KEY_MUTE and is read from hidraw.
"""

import glob
import json
import os
import select
import subprocess
import sys
import time

from evdev import InputDevice
from evdev import ecodes

VOLUME_UP = ecodes.KEY_VOLUMEUP
VOLUME_DOWN = ecodes.KEY_VOLUMEDOWN
KEY_UNRELATED = ecodes.KEY_ESC
PHONE_MUTE_BIT = 0x04
VENDOR = 0x0B0E
PRODUCT = 0x2475
DEVICE_NAME = "Jabra Speak 710"
RETRY_SECONDS = 1.0
HID_RETRY_SECONDS = 2.0


def volume_step(code, value):
    """Return "up", "down", or None. A press is value 1."""
    if value != 1:
        return None
    if code == VOLUME_UP:
        return "up"
    if code == VOLUME_DOWN:
        return "down"
    return None


def mute_edge(report, held):
    """Return (toggle, held). Toggle on the rising edge of phone-mute."""
    if len(report) < 2 or report[0] != 2:
        return False, held
    pressed = bool(report[1] & PHONE_MUTE_BIT)
    return (pressed and not held), pressed


def node_id_from_dump(data, media_class):
    """Return the PipeWire object id for the Jabra node of media_class."""
    if not isinstance(data, list):
        return None
    for obj in data:
        if obj.get("type") != "PipeWire:Interface:Node":
            continue
        props = (obj.get("info") or {}).get("props") or {}
        if props.get("media.class") != media_class:
            continue
        blob = " ".join(
            str(props.get(key, ""))
            for key in (
                "node.description",
                "node.nick",
                "node.name",
                "device.description",
            )
        ).lower()
        if "jabra" not in blob:
            continue
        ident = obj.get("id")
        if ident is None:
            ident = props.get("object.id")
        if ident is not None:
            return str(ident)
    return None


def volume_argv(sink_id, action):
    if action == "up":
        return ["wpctl", "set-volume", "-l", "1", sink_id, "2.5%+"]
    if action == "down":
        return ["wpctl", "set-volume", sink_id, "2.5%-"]
    raise ValueError(action)


def mute_argv(source_id):
    return ["wpctl", "set-mute", source_id, "toggle"]


def event_node(sysfs_root="/sys"):
    pattern = os.path.join(sysfs_root, "class/input/event*/device/name")
    for name_path in sorted(glob.glob(pattern)):
        try:
            with open(name_path, encoding="utf-8", errors="ignore") as handle:
                name = handle.read().strip()
        except OSError:
            continue
        if name != DEVICE_NAME:
            continue
        event_dir = os.path.basename(os.path.dirname(os.path.dirname(name_path)))
        return os.path.join("/dev/input", event_dir)
    return None


def hid_id_from_uevent(text):
    for line in text.splitlines():
        if not line.startswith("HID_ID="):
            continue
        parts = line.split("=", 1)[1].split(":")
        if len(parts) < 3:
            return None
        try:
            return int(parts[1], 16), int(parts[2], 16)
        except ValueError:
            return None
    return None


def hidraw_node(sysfs_root="/sys"):
    pattern = os.path.join(sysfs_root, "class/hidraw/hidraw*/device/uevent")
    for uevent_path in sorted(glob.glob(pattern)):
        try:
            with open(uevent_path, encoding="utf-8", errors="ignore") as handle:
                text = handle.read()
        except OSError:
            continue
        if hid_id_from_uevent(text) != (VENDOR, PRODUCT):
            continue
        node = os.path.basename(os.path.dirname(os.path.dirname(uevent_path)))
        return os.path.join("/dev", node)
    return None


class PipeWireNodes:
    """Cache Jabra sink and source ids. Drop the cache when wpctl fails."""

    def __init__(self, dump):
        self._dump = dump
        self.sink = None
        self.source = None

    def id_for(self, media_class):
        cached = self.sink if media_class == "Audio/Sink" else self.source
        if cached is not None:
            return cached
        ident = node_id_from_dump(self._dump(), media_class)
        if media_class == "Audio/Sink":
            self.sink = ident
        else:
            self.source = ident
        return ident

    def invalidate(self):
        self.sink = None
        self.source = None


def pw_dump():
    raw = subprocess.check_output(["pw-dump"], text=True)
    return json.loads(raw)


def run_wpctl(argv):
    completed = subprocess.run(argv, check=False)
    return completed.returncode == 0


def apply_volume(nodes, action, run=run_wpctl):
    sink_id = nodes.id_for("Audio/Sink")
    if sink_id is None:
        print("no Jabra sink", file=sys.stderr)
        return False
    if run(volume_argv(sink_id, action)):
        return True
    nodes.invalidate()
    sink_id = nodes.id_for("Audio/Sink")
    if sink_id is None:
        print("no Jabra sink", file=sys.stderr)
        return False
    return run(volume_argv(sink_id, action))


def apply_mute(nodes, run=run_wpctl):
    source_id = nodes.id_for("Audio/Source")
    if source_id is None:
        print("no Jabra source", file=sys.stderr)
        return False
    if run(mute_argv(source_id)):
        return True
    nodes.invalidate()
    source_id = nodes.id_for("Audio/Source")
    if source_id is None:
        print("no Jabra source", file=sys.stderr)
        return False
    return run(mute_argv(source_id))


def open_hidraw():
    path = hidraw_node()
    if path is None:
        return None
    try:
        return os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    except OSError as exc:
        print(f"hidraw {path}: {exc}", file=sys.stderr)
        return None


def watch_device(event_path, nodes):
    dev = InputDevice(event_path)
    hid = None
    try:
        try:
            dev.grab()
        except OSError as exc:
            print(f"grab {event_path} failed: {exc}", file=sys.stderr)
        else:
            print(f"grabbed {event_path}", file=sys.stderr)
        hid = open_hidraw()
        next_hid = time.monotonic() + HID_RETRY_SECONDS
        mute_held = False
        poller = select.poll()
        poller.register(dev.fd, select.POLLIN)
        if hid is not None:
            poller.register(hid, select.POLLIN)
        while True:
            if hid is None and time.monotonic() >= next_hid:
                hid = open_hidraw()
                next_hid = time.monotonic() + HID_RETRY_SECONDS
                if hid is not None:
                    poller.register(hid, select.POLLIN)
                    print("opened hidraw", file=sys.stderr)
            ready = poller.poll(500)
            for fd, _mask in ready:
                if fd == dev.fd:
                    try:
                        events = list(dev.read())
                    except BlockingIOError:
                        continue
                    for event in events:
                        if event.type != ecodes.EV_KEY:
                            continue
                        action = volume_step(event.code, event.value)
                        if action is not None:
                            apply_volume(nodes, action)
                elif hid is not None and fd == hid:
                    try:
                        report = os.read(hid, 64)
                    except BlockingIOError:
                        continue
                    toggle, mute_held = mute_edge(report, mute_held)
                    if toggle:
                        apply_mute(nodes)
    finally:
        if hid is not None:
            os.close(hid)
        dev.close()


def watch():
    nodes = PipeWireNodes(pw_dump)
    while True:
        path = event_node()
        if path is None:
            time.sleep(RETRY_SECONDS)
            continue
        try:
            watch_device(path, nodes)
        except OSError as exc:
            print(f"{path}: {exc}", file=sys.stderr)
            time.sleep(RETRY_SECONDS)


def self_test():
    failures = []

    def check(name, got, want):
        if got != want:
            failures.append(f"{name}: got {got!r} want {want!r}")

    check("release", volume_step(VOLUME_UP, 0), None)
    check("up", volume_step(VOLUME_UP, 1), "up")
    check("up again", volume_step(VOLUME_UP, 1), "up")
    check("down", volume_step(VOLUME_DOWN, 1), "down")
    check("unrelated", volume_step(KEY_UNRELATED, 1), None)
    check("repeat", volume_step(VOLUME_UP, 2), None)

    toggle, held = mute_edge(b"\x02\x04\x00", False)
    check("mute press", (toggle, held), (True, True))
    toggle, held = mute_edge(b"\x02\x00\x00", held)
    check("mute release", (toggle, held), (False, False))
    toggle, held = mute_edge(b"\x02\x04\x00", held)
    check("mute again", (toggle, held), (True, True))
    toggle, _held = mute_edge(b"\x01\x04", False)
    check("consumer report", toggle, False)
    toggle, held = mute_edge(b"\x02", False)
    check("short report", (toggle, held), (False, False))

    dump = [
        {
            "id": 65,
            "type": "PipeWire:Interface:Node",
            "info": {
                "props": {
                    "media.class": "Audio/Sink",
                    "node.description": "Jabra Speak 710",
                }
            },
        },
        {
            "id": 9,
            "type": "PipeWire:Interface:Node",
            "info": {
                "props": {
                    "media.class": "Audio/Source",
                    "node.name": "alsa_input.jabra",
                }
            },
        },
        {
            "id": 3,
            "type": "PipeWire:Interface:Node",
            "info": {"props": {"media.class": "Audio/Sink", "node.name": "soundbar"}},
        },
    ]
    check("sink", node_id_from_dump(dump, "Audio/Sink"), "65")
    check("source", node_id_from_dump(dump, "Audio/Source"), "9")
    check("missing", node_id_from_dump({}, "Audio/Sink"), None)
    check(
        "up argv",
        volume_argv("65", "up"),
        ["wpctl", "set-volume", "-l", "1", "65", "2.5%+"],
    )
    check(
        "down argv",
        volume_argv("65", "down"),
        ["wpctl", "set-volume", "65", "2.5%-"],
    )
    check("mute argv", mute_argv("101"), ["wpctl", "set-mute", "101", "toggle"])

    calls = []

    def record(argv):
        calls.append(argv)
        return argv[-1] != "fail"

    nodes = PipeWireNodes(lambda: dump)
    check("apply up", apply_volume(nodes, "up", record), True)
    nodes.sink = "stale"
    dump_box = {"fail": True}

    def flaky_dump():
        if dump_box["fail"]:
            return []
        return dump

    def flaky_run(argv):
        calls.append(argv)
        return "stale" not in argv

    nodes = PipeWireNodes(flaky_dump)
    nodes.sink = "stale"
    check("retry", apply_volume(nodes, "down", flaky_run), False)
    dump_box["fail"] = False
    nodes = PipeWireNodes(flaky_dump)
    nodes.sink = "stale"
    check("retry ok", apply_volume(nodes, "down", flaky_run), True)

    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    print("ok")
    return 0


def main(argv):
    if len(argv) == 2 and argv[1] == "watch":
        watch()
        return 0
    if len(argv) == 2 and argv[1] == "self-test":
        return self_test()
    print("Usage: jabra-pads.py watch|self-test", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
