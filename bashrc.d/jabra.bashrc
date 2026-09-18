#!/usr/bin/env bash
# Set the Jabra Speak PipeWire sink volume as a percent.
#   jabra-volume 50
#   jabra-volume 100%

_jabra_sink_id() {
    pw-dump | python3 -c '
import json, sys
data = json.load(sys.stdin)
if not isinstance(data, list):
    raise SystemExit(1)
for obj in data:
    if obj.get("type") != "PipeWire:Interface:Node":
        continue
    props = (obj.get("info") or {}).get("props") or {}
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
        print(ident)
        raise SystemExit(0)
raise SystemExit(1)
'
}

function jabra-volume() {
    if [[ $# -ne 1 ]]; then
        printf 'usage: jabra-volume PERCENT\n' >&2
        return 2
    fi
    local pct="${1%"%"}"
    if [[ ! "$pct" =~ ^[0-9]+$ ]] || (( pct > 100 )); then
        printf 'usage: jabra-volume PERCENT\n' >&2
        return 2
    fi
    local sink
    sink="$(_jabra_sink_id)" || {
        printf 'no Jabra sink\n' >&2
        return 1
    }
    wpctl set-volume -l 1 "$sink" "${pct}%"
}
