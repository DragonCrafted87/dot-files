#!/usr/bin/env bash
# Wake outputs after idle. Do not re-run the full profile apply here;
# that path rewrites every monitor and can fight HDMI disable/enable.

PROFILE="${HOME}/.config/hypr/scripts/display-profile.sh"

WALLPAPER="${HOME}/.config/hypr/scripts/astro-wallpaper.sh"

dpms_fallback() {
    action="$1"
    if hyprctl keyword misc:disable_xdg_env_checks true 2>&1 | grep -q 'Use eval'; then
        hyprctl dispatch "hl.dsp.dpms({ action = \"${action}\" })" >/dev/null 2>&1 || true
        return 0
    fi
    hyprctl dispatch dpms "$action" >/dev/null 2>&1 || true
}

run_boinc_gpu() {
    mode="$1"
    cmd=""
    if [ -n "${BOINC_GPU_BIN:-}" ] && [ -x "$BOINC_GPU_BIN" ]; then
        "$BOINC_GPU_BIN" "$mode" >/dev/null 2>&1 || true
        return 0
    fi
    if [ -f "${HOME}/.config/dot-files/root" ]; then
        root="$(tr -d '[:space:]' <"${HOME}/.config/dot-files/root")"
        if [ -n "$root" ] && [ -x "${root}/setup/files/boinc/boinc-gpu.sh" ]; then
            cmd="${root}/setup/files/boinc/boinc-gpu.sh"
        fi
    fi
    if [ -z "$cmd" ] && [ -x /usr/local/bin/boinc-gpu ]; then
        cmd=/usr/local/bin/boinc-gpu
    fi
    if [ -z "$cmd" ] && [ -x "${HOME}/dot-files/setup/files/boinc/boinc-gpu.sh" ]; then
        cmd="${HOME}/dot-files/setup/files/boinc/boinc-gpu.sh"
    fi
    if [ -n "$cmd" ]; then
        "$cmd" "$mode" >/dev/null 2>&1 || true
    fi
}

if [ -x "$PROFILE" ]; then
    "$PROFILE" idle-on
else
    echo "display-profile.sh missing; falling back to dpms on" >&2
    dpms_fallback on
fi

# The 06:30 refresh only writes stills for outputs that are enabled then.
# Re-apply after wake so a monitor idle had disabled gets one. apply
# no-ops when the conf already matches.
if [ -x "$WALLPAPER" ]; then
    "$WALLPAPER" apply || true
fi

run_boinc_gpu active
