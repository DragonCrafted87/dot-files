#!/usr/bin/env bash
# Run a hypr* tool from the compositor that owns this session.
# Distro Hyprland -> /usr. Source prefix -> /opt/hyprland.
set -euo pipefail

PREFIX="${HYPRLAND_SOURCE_PREFIX:-/opt/hyprland}"
cmd="${1:-}"
shift || true

if [[ -z "$cmd" ]]; then
    printf 'usage: hypr-session-exec.sh COMMAND [args]\n' >&2
    exit 1
fi

compositor_exe() {
    local uid sig pid
    uid="$(id -u)"
    sig="${HYPRLAND_INSTANCE_SIGNATURE:-}"
    while read -r pid; do
        [[ -n "$pid" ]] || continue
        if [[ -n "$sig" ]]; then
            tr '\0' '\n' <"/proc/${pid}/environ" 2>/dev/null |
                grep -Fxq "HYPRLAND_INSTANCE_SIGNATURE=${sig}" || continue
        fi
        readlink -f "/proc/${pid}/exe" 2>/dev/null
        return 0
    done < <(pgrep -u "$uid" -x Hyprland || true)
    return 1
}

exe="$(compositor_exe || true)"
if [[ "$exe" == "${PREFIX}/bin/Hyprland" ]]; then
    export PATH="${PREFIX}/bin:${PATH:-/usr/bin}"
    export LD_LIBRARY_PATH="${PREFIX}/lib64:${PREFIX}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
    export XDG_DATA_DIRS="${PREFIX}/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    if [[ -x "${PREFIX}/bin/${cmd}" ]]; then
        exec "${PREFIX}/bin/${cmd}" "$@"
    fi
    if [[ -x "${PREFIX}/libexec/${cmd}" ]]; then
        exec "${PREFIX}/libexec/${cmd}" "$@"
    fi
    printf 'hypr-session-exec: missing %s in %s\n' "$cmd" "$PREFIX" >&2
    exit 1
fi

if command -v "$cmd" >/dev/null 2>&1; then
    exec "$cmd" "$@"
fi
if [[ -x "/usr/bin/${cmd}" ]]; then
    exec "/usr/bin/${cmd}" "$@"
fi
if [[ -x "/usr/libexec/${cmd}" ]]; then
    exec "/usr/libexec/${cmd}" "$@"
fi
printf 'hypr-session-exec: %s not found\n' "$cmd" >&2
exit 1
