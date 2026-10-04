#!/usr/bin/env bash
# Proves Ventoy mount detection for the ward-drake HAOS installer.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# shellcheck disable=SC1091
. "${repo}/setup/ventoy/ward-drake/install-haos.sh"

bin="${work}/bin"
mkdir -p "$bin"
find_log="${work}/findmnt.log"

cat >"${bin}/findmnt" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${FIND_LOG:?}"
if [[ "$*" == *"-T "* ]]; then
    printf '%s\n' "${FIND_OPTS:-}"
    exit 0
fi
if [[ "$*" == *"LABEL=Ventoy"* ]]; then
    [[ -n "${FIND_LABEL:-}" ]] && printf '%s\n' "$FIND_LABEL"
    exit 0
fi
[[ -n "${FIND_DEV:-}" ]] && printf '%s\n' "$FIND_DEV"
exit 0
EOF
cat >"${bin}/mount" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${MOUNT_LOG:?}"
exit 0
EOF
chmod 0755 "${bin}/findmnt" "${bin}/mount"

image_at() {
    local dir="$1"
    mkdir -p "${dir}/raw-disc-images"
    : >"${dir}/raw-disc-images/haos_generic-x86-64-18.3.img.xz"
}

run_mount() {
    PATH="${bin}:${PATH}" \
        FIND_LOG="$find_log" \
        MOUNT_LOG="${work}/mount.log" \
        FIND_DEV="${FIND_DEV:-}" \
        FIND_LABEL="${FIND_LABEL:-}" \
        HAOS_LIVE_MEDIA="${work}/media" \
        HAOS_LIVE_RUN_MEDIA="${work}/run-media" \
        HAOS_VENTOY_MNT="${work}/mnt-ventoy" \
        ventoy_mount_point /dev/sda1
}

: >"$find_log"
: >"${work}/mount.log"
FIND_DEV="${work}/by-device"
image_at "$FIND_DEV"
got="$(run_mount)"
[[ "$got" == "$FIND_DEV" ]] || {
    printf 'device mount was skipped: %s\n' "$got" >&2
    exit 1
}
[[ ! -s "${work}/mount.log" ]] || {
    printf 'device mount called mount:\n%s\n' "$(cat "${work}/mount.log")" >&2
    exit 1
}

: >"$find_log"
: >"${work}/mount.log"
FIND_DEV="${work}/empty-mount"
mkdir -p "$FIND_DEV"
FIND_LABEL=""
image_at "${work}/media/live/Ventoy"
got="$(run_mount)"
[[ "$got" == "${work}/media/live/Ventoy" ]] || {
    printf 'live desktop mount was skipped: %s\n' "$got" >&2
    exit 1
}
[[ ! -s "${work}/mount.log" ]] || {
    printf 'live desktop mount called mount:\n%s\n' "$(cat "${work}/mount.log")" >&2
    exit 1
}

: >"$find_log"
: >"${work}/mount.log"
FIND_DEV=""
rm -rf "${work}/media" "${work}/run-media"
got="$(run_mount)"
[[ "$got" == "${work}/mnt-ventoy" ]] || {
    printf 'unmounted stick was not mounted at the fallback: %s\n' "$got" >&2
    exit 1
}
grep -q -- '-o ro /dev/sda1' "${work}/mount.log" || {
    printf 'fallback mount command:\n%s\n' "$(cat "${work}/mount.log")" >&2
    exit 1
}

printf 'haos install mount ok\n'
