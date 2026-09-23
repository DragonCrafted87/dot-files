#!/usr/bin/env bash
# Console helpers for per-monitor astronomy wallpapers.

_astro_wallpaper() {
    local script="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/astro-wallpaper.sh"
    if [[ ! -f "$script" ]]; then
        printf 'missing %s\n' "$script" >&2
        return 1
    fi
    "$script" "$@"
}

astro-wallpaper() { _astro_wallpaper "${1:-apply}"; }
astro-wallpaper-refresh() { _astro_wallpaper refresh; }
astro-wallpaper-status() { _astro_wallpaper status; }
