"""Change volume on the sink that currently has playback, not only the default."""

import json
import subprocess
import sys


def usage():
    print("Usage: adjust_volume.py raise|lower|mute|micmute", file=sys.stderr)
    raise SystemExit(1)


def pw_dump():
    try:
        raw = subprocess.check_output(["pw-dump"], text=True)
        data = json.loads(raw)
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError):
        return []
    if isinstance(data, list):
        return data
    return []


def node_props(obj):
    info = obj.get("info") or {}
    props = info.get("props") or {}
    return props if isinstance(props, dict) else {}


def node_id(obj):
    ident = obj.get("id")
    if ident is None:
        ident = node_props(obj).get("object.id")
    return ident


def running_output_streams(objects):
    streams = []
    for obj in objects:
        if obj.get("type") != "PipeWire:Interface:Node":
            continue
        props = node_props(obj)
        if props.get("media.class") != "Stream/Output/Audio":
            continue
        state = (obj.get("info") or {}).get("state")
        if state not in {"running", "streaming"}:
            continue
        streams.append(obj)
    return streams


def sink_ids(objects):
    found = {}
    for obj in objects:
        if obj.get("type") != "PipeWire:Interface:Node":
            continue
        props = node_props(obj)
        if props.get("media.class") != "Audio/Sink":
            continue
        ident = node_id(obj)
        if ident is None:
            continue
        found[int(ident)] = props
    return found


def source_ids(objects):
    found = {}
    for obj in objects:
        if obj.get("type") != "PipeWire:Interface:Node":
            continue
        props = node_props(obj)
        if props.get("media.class") != "Audio/Source":
            continue
        ident = node_id(obj)
        if ident is None:
            continue
        found[int(ident)] = props
    return found


def links_to_node(objects, stream_id):
    targets = []
    for obj in objects:
        if obj.get("type") != "PipeWire:Interface:Link":
            continue
        info = obj.get("info") or {}
        output_node = info.get("output-node-id")
        input_node = info.get("input-node-id")
        if output_node == stream_id and input_node is not None:
            targets.append(int(input_node))
    return targets


def prefer_name(props_list, needle):
    needle = needle.lower()
    for ident, props in props_list:
        blob = " ".join(
            str(props.get(key, ""))
            for key in ("node.description", "node.nick", "node.name", "device.description")
        ).lower()
        if needle in blob:
            return ident
    return None


def active_sink(objects):
    sinks = sink_ids(objects)
    hits = []
    for stream in running_output_streams(objects):
        stream_ident = node_id(stream)
        if stream_ident is None:
            continue
        for target in links_to_node(objects, int(stream_ident)):
            if target in sinks:
                hits.append((target, sinks[target]))
    if hits:
        jabra = prefer_name(hits, "jabra")
        if jabra is not None:
            return str(jabra)
        return str(hits[0][0])
    return "@DEFAULT_AUDIO_SINK@"


def running_input_streams(objects):
    streams = []
    for obj in objects:
        if obj.get("type") != "PipeWire:Interface:Node":
            continue
        props = node_props(obj)
        if props.get("media.class") != "Stream/Input/Audio":
            continue
        state = (obj.get("info") or {}).get("state")
        if state not in {"running", "streaming"}:
            continue
        streams.append(obj)
    return streams


def active_source(objects):
    sources = source_ids(objects)
    hits = []
    for stream in running_input_streams(objects):
        stream_ident = node_id(stream)
        if stream_ident is None:
            continue
        for obj in objects:
            if obj.get("type") != "PipeWire:Interface:Link":
                continue
            info = obj.get("info") or {}
            if info.get("input-node-id") == int(stream_ident):
                origin = info.get("output-node-id")
                if origin in sources:
                    hits.append((int(origin), sources[int(origin)]))
    if hits:
        jabra = prefer_name(hits, "jabra")
        if jabra is not None:
            return str(jabra)
        return str(hits[0][0])
    return "@DEFAULT_AUDIO_SOURCE@"


def wpctl(*args):
    subprocess.check_call(["wpctl", *args])


def main(argv):
    if len(argv) != 2 or argv[1] in {"-h", "--help", "help"}:
        usage()
    action = argv[1]
    objects = pw_dump()
    if action == "raise":
        wpctl("set-volume", "-l", "1", active_sink(objects), "5%+")
        return 0
    if action == "lower":
        wpctl("set-volume", active_sink(objects), "5%-")
        return 0
    if action == "mute":
        wpctl("set-mute", active_sink(objects), "toggle")
        return 0
    if action == "micmute":
        wpctl("set-mute", active_source(objects), "toggle")
        return 0
    usage()
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
