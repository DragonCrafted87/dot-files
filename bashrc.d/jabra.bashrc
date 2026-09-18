#!/usr/bin/env bash
# Jabra Speak PipeWire helpers.
#   jabra-volume 50
#   jabra-volume 100%
#   jabra-mute
#   jabra-unmute

_jabra_node_id() {
    local class="$1"
    pw-dump | python3 -c '
import json, sys
want = sys.argv[1]
data = json.load(sys.stdin)
if not isinstance(data, list):
    raise SystemExit(1)
for obj in data:
    if obj.get("type") != "PipeWire:Interface:Node":
        continue
    props = (obj.get("info") or {}).get("props") or {}
    if props.get("media.class") != want:
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
' "$class"
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
    sink="$(_jabra_node_id Audio/Sink)" || {
        printf 'no Jabra sink\n' >&2
        return 1
    }
    wpctl set-volume -l 1 "$sink" "${pct}%"
}

function jabra-mute() {
    local source
    source="$(_jabra_node_id Audio/Source)" || {
        printf 'no Jabra source\n' >&2
        return 1
    }
    wpctl set-mute "$source" 1
}

function jabra-unmute() {
    local source
    source="$(_jabra_node_id Audio/Source)" || {
        printf 'no Jabra source\n' >&2
        return 1
    }
    wpctl set-mute "$source" 0
}
