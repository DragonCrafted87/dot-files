#!/usr/bin/env bash
# Classifier and reconnect predicate for idle-display-watch.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROFILE="${ROOT}/config/hypr/scripts/display-profile.sh"
WATCH="${ROOT}/config/hypr/scripts/idle-display-watch.sh"

fail() {
    printf 'idle-display-wake-test: %s\n' "$*" >&2
    exit 1
}

assert_eq() {
    local got="$1" want="$2" label="$3"
    [[ "$got" == "$want" ]] || fail "${label}: got [${got}] want [${want}]"
}

classify_cases() {
    # shellcheck disable=SC1090
    source "$PROFILE"
    local json got

    json='[{"name":"HDMI-A-1","disabled":false,"dpmsStatus":true,"width":2560}]'
    got="$(printf '%s' "$json" | classify_monitor_dpms HDMI-A-1)"
    assert_eq "$got" 0 "dpms on"

    json='[{"name":"HDMI-A-1","disabled":false,"dpmsStatus":false,"width":2560}]'
    got="$(printf '%s' "$json" | classify_monitor_dpms HDMI-A-1)"
    assert_eq "$got" 1 "dpms off"

    json='[{"name":"DP-2","disabled":false,"dpmsStatus":true}]'
    got="$(printf '%s' "$json" | classify_monitor_dpms HDMI-A-1)"
    assert_eq "$got" 2 "missing output"

    json='[{"name":"HDMI-A-1","disabled":true,"dpmsStatus":false}]'
    got="$(printf '%s' "$json" | classify_monitor_dpms HDMI-A-1)"
    assert_eq "$got" 3 "disabled output"

    json='not-json'
    got="$(printf '%s' "$json" | classify_monitor_dpms HDMI-A-1)"
    assert_eq "$got" 2 "bad json"
}

wake_cases() {
    local tmp status log
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" EXIT
    export XDG_STATE_HOME="${tmp}/state"
    export MOCK_LOG="${tmp}/mock.log"
    mkdir -p "${XDG_STATE_HOME}/hypr" "${tmp}/drm/card0-HDMI-A-1" "${tmp}/bin"
    cat >"${tmp}/bin/mock-profile" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"${MOCK_LOG}"
EOF
    chmod +x "${tmp}/bin/mock-profile"
    # shellcheck disable=SC1090
    source "$WATCH"
    PROFILE_SH="${tmp}/bin/mock-profile"
    status="${tmp}/drm/card0-HDMI-A-1/status"

    printf 'connected\n' >"$status"
    : >"$MOCK_LOG"
    on_status_file "$status"
    log="$(cat "$MOCK_LOG")"
    assert_eq "$log" "wake-dpms HDMI-A-1" "connected and awake"

    printf '1\n' >"$BLANKED_FILE"
    : >"$MOCK_LOG"
    on_status_file "$status"
    log="$(cat "$MOCK_LOG")"
    assert_eq "$log" "" "connected while blanked"

    rm -f "$BLANKED_FILE"
    printf 'disconnected\n' >"$status"
    : >"$MOCK_LOG"
    on_status_file "$status"
    log="$(cat "$MOCK_LOG")"
    assert_eq "$log" "" "disconnected while awake"

    printf 'connected\n' >"$status"
    printf '1\n' >"$BLANKED_FILE"
    : >"$MOCK_LOG"
    on_status_file "$status"
    log="$(cat "$MOCK_LOG")"
    assert_eq "$log" "" "blanked still blocks after a disconnect"

    rm -f "$BLANKED_FILE"
    : >"$MOCK_LOG"
    on_status_file "$status"
    log="$(cat "$MOCK_LOG")"
    assert_eq "$log" "wake-dpms HDMI-A-1" "clearing the blank allows the next connect"
    rm -rf "$tmp"
    trap - EXIT
}

stamp_short_circuit() {
    local tmp
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" EXIT
    mkdir -p "${tmp}/hypr" "${tmp}/bin"
    printf '1\n' >"${tmp}/hypr/idle-blanked"
    cat >"${tmp}/bin/hyprctl" <<'EOF'
#!/bin/bash
printf 'called\n' >"${HYPRCTL_MARK}"
exit 99
EOF
    chmod +x "${tmp}/bin/hyprctl"
    HYPRCTL_MARK="${tmp}/called" PATH="${tmp}/bin:${PATH}" XDG_STATE_HOME="$tmp" \
        "$PROFILE" wake-dpms HDMI-A-1
    [[ ! -f "${tmp}/called" ]] || fail "wake-dpms called hyprctl while blanked"
}

classify_cases
wake_cases
stamp_short_circuit
printf 'idle-display-wake-test: ok\n'
