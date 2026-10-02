#!/usr/bin/env bash
# GPU mode follows the display, hypridle is enabled with the source
# install, and BOINC is built and run with an OpenCL platform.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0

note() {
    printf 'fail: %s\n' "$*" >&2
    fail=1
}

on="${repo}/config/hypr/scripts/idle-display-on.sh"
off="${repo}/config/hypr/scripts/idle-display-off.sh"
gpu="${repo}/setup/files/boinc/boinc-gpu.sh"
defs="${repo}/setup/modules/compute/install-boinc-defs.sh"
source_mod="${repo}/setup/modules/desktop/install-hyprland-source.sh"
session="${repo}/config/hypr/scripts/graphical-session.sh"

grep -q 'hyprctl dispatch dpms on' "$on" && note "idle-display-on still dispatches legacy dpms on"
grep -q 'hyprctl dispatch dpms off' "$off" && note "idle-display-off still dispatches legacy dpms off"
[[ -x "$gpu" ]] || note "missing executable ${gpu}"
grep -q 'lib64RusticlOpenCL' "$defs" || note "runtime deps omit lib64RusticlOpenCL"
grep -q 'RUSTICL_ENABLE=radeonsi' "${repo}/setup/files/boinc/boinc-client.service" \
    || note "boinc client unit does not enable Rusticl radeonsi"
grep -q 'opencl-headers' "$defs" || note "build deps omit opencl-headers"
grep -q 'boinc_opencl_linked' "$defs" || note "stamp check does not require a linked OpenCL API"
grep -q 'libboinc_opencl_la_LIBADD' "$defs" || note "build does not link libboinc_opencl against OpenCL"
grep -q 'enable_source_session_units' "$source_mod" || note "source install never enables session units"

python3 - "$source_mod" <<'PY' || note "stamp-current path does not enable hypridle"
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text()
start = text.index("prefix already current")
chunk = text[start : text.index("exit 0", start)]
if "enable_source_session_units" not in chunk:
    raise SystemExit(1)
PY

grep -q 'start hypridle.service' "$session" || note "graphical session does not start hypridle"
grep -q 'boinc-gpu' "$session" || note "graphical session does not set BOINC GPU mode"

if [[ "$fail" -ne 0 ]]; then
    exit 1
fi

# shellcheck disable=SC1091
. "$defs"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "${work}/prefix/bin" "${work}/prefix/lib" "${work}/prefix/share/boinc"
for bin in boinc boincmgr boinccmd; do
    printf '#!/bin/sh\n' >"${work}/prefix/bin/${bin}"
    chmod 0755 "${work}/prefix/bin/${bin}"
done
printf '%s\n' "$BOINC_VERSION" >"${work}/prefix/share/boinc/.dotfiles-version"
printf 'placeholder\n' >"${work}/prefix/lib/libboinc_opencl.so"

BOINC_PREFIX="${work}/prefix"
STAMP="${BOINC_PREFIX}/share/boinc/.dotfiles-version"
ldd() {
    printf '%s\n' "libstdc++.so.6 => /lib64/libstdc++.so.6"
}
if boinc_already_built; then
    note "already-built treats an unlinked OpenCL API as finished"
fi
ldd() {
    printf '%s\n' "libOpenCL.so.1 => /lib64/libOpenCL.so.1"
}
if ! boinc_already_built; then
    note "already-built rejects an OpenCL-linked API"
fi
unset -f ldd

if [[ "$fail" -ne 0 ]]; then
    exit 1
fi

mkdir -p "${work}/home/.config/hypr/scripts" "${work}/bin"
printf 'secret\n' >"${work}/gui_rpc_auth.cfg"
cat >"${work}/bin/systemctl" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"${work}/bin/boinccmd" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${BOINC_GPU_LOG:?}"
EOF
chmod 0755 "${work}/bin/systemctl" "${work}/bin/boinccmd"

python3 - "${work}/port" <<'PY' &
import socket
import sys

path = sys.argv[1]
server = socket.socket()
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(("127.0.0.1", 0))
server.listen(8)
server.settimeout(20)
with open(path, "w", encoding="ascii") as handle:
    handle.write(str(server.getsockname()[1]))
while True:
    try:
        client, _addr = server.accept()
    except socket.timeout:
        break
    client.close()
PY
listener=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
    [[ -s "${work}/port" ]] && break
    sleep 0.1
done
port="$(cat "${work}/port")"

run_gpu() {
    local mode="$1"
    : >"${work}/gpu.log"
    PATH="${work}/bin:${PATH}" \
        BOINC_GPU_LOG="${work}/gpu.log" \
        BOINC_DIR="${work}" \
        BOINC_HOST="127.0.0.1" \
        BOINC_PORT="$port" \
        BOINCCMD="${work}/bin/boinccmd" \
        "$gpu" "$mode"
}

run_gpu idle
grep -q -- '--set_gpu_mode always' "${work}/gpu.log" || note "idle did not set gpu mode always: $(cat "${work}/gpu.log")"
grep -q -- '--passwd secret' "${work}/gpu.log" || note "idle did not pass the rpc password"
run_gpu active
grep -q -- '--set_gpu_mode never' "${work}/gpu.log" || note "active did not set gpu mode never: $(cat "${work}/gpu.log")"

cat >"${work}/home/.config/hypr/scripts/display-profile.sh" <<'EOF'
#!/bin/sh
printf '%s\n' "$1" >>"${PROFILE_LOG:?}"
EOF
chmod 0755 "${work}/home/.config/hypr/scripts/display-profile.sh"
cat >"${work}/boinc-gpu-stub" <<'EOF'
#!/bin/sh
printf '%s\n' "$1" >>"${GPU_MODE_LOG:?}"
EOF
chmod 0755 "${work}/boinc-gpu-stub"

HOME="${work}/home" PROFILE_LOG="${work}/profile.log" GPU_MODE_LOG="${work}/mode.log" \
    BOINC_GPU_BIN="${work}/boinc-gpu-stub" "$off"
HOME="${work}/home" PROFILE_LOG="${work}/profile.log" GPU_MODE_LOG="${work}/mode.log" \
    BOINC_GPU_BIN="${work}/boinc-gpu-stub" "$on"
grep -q 'idle-off' "${work}/profile.log" || note "idle-off did not call the profile script"
grep -q 'idle-on' "${work}/profile.log" || note "idle-on did not call the profile script"
modes="$(cat "${work}/mode.log")"
[[ "$modes" == $'idle\nactive' ]] || note "display scripts passed modes: ${modes}"

kill "$listener" 2>/dev/null || true
wait "$listener" 2>/dev/null || true

if [[ "$fail" -ne 0 ]]; then
    exit 1
fi
printf 'ok\n'
