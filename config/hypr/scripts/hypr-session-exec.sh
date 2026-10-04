#!/usr/bin/env bash
# Run a hypr* tool for the compositor that owns this session.
# /usr/local is the source install. /opt/hyprland is a leftover prefix.
# A distro session still uses /usr.
set -euo pipefail

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

run_from() {
    local root="$1"
    shift
    if [[ -x "${root}/bin/${cmd}" ]]; then
        exec "${root}/bin/${cmd}" "$@"
    fi
    if [[ -x "${root}/libexec/${cmd}" ]]; then
        exec "${root}/libexec/${cmd}" "$@"
    fi
    printf 'hypr-session-exec: missing %s in %s\n' "$cmd" "$root" >&2
    exit 1
}

exe="$(compositor_exe || true)"
case "$exe" in
    /usr/local/bin/Hyprland)
        export PATH="/usr/local/bin:${PATH:-/usr/bin}"
        export XKB_CONFIG_ROOT="${XKB_CONFIG_ROOT:-/usr/share/X11/xkb}"
        unset LD_LIBRARY_PATH
        run_from /usr/local "$@"
        ;;
    /opt/hyprland/bin/Hyprland)
        export PATH="/opt/hyprland/bin:${PATH:-/usr/bin}"
        export LD_LIBRARY_PATH="/opt/hyprland/lib64:/opt/hyprland/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
        export XDG_DATA_DIRS="/opt/hyprland/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
        export XKB_CONFIG_ROOT="${XKB_CONFIG_ROOT:-/usr/share/X11/xkb}"
        run_from /opt/hyprland "$@"
        ;;
esac

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
