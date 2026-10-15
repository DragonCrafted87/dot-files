#!/usr/bin/env bash
# Blank outputs through the host/profile script so new machines do not need
# another HDMI special case here.

PROFILE="${HOME}/.config/hypr/scripts/display-profile.sh"

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
    "$PROFILE" idle-off
else
    echo "display-profile.sh missing; falling back to dpms off" >&2
    dpms_fallback off
fi

run_boinc_gpu idle
