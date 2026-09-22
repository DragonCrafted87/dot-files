#!/usr/bin/env bash
# Force a Piper/ratbag profile after Windows G HUB rewrites onboard storage.
# Piper has no CLI; ratbagctl talks to ratbagd (same backend).
# Started by udev via reset-piper-profile.service, or by hand.
set -euo pipefail

PROFILE="${PIPER_PROFILE:-0}"
MATCH="${PIPER_DEVICE_MATCH:-G603}"
ATTEMPTS="${PIPER_ATTEMPTS:-12}"
RETRY_SLEEP="${PIPER_RETRY_SLEEP:-0.5}"
QUIET="${PIPER_QUIET:-0}"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
LOCK_FILE="${STATE_DIR}/reset-piper-profile.lock"

usage() {
    cat <<'EOF'
Usage: reset-piper-profile.sh [apply|status|help]

apply   Set matching ratbag devices to profile 0 (default).
status  Print ratbag devices and the active profile.

Piper is GUI-only. This uses ratbagctl against ratbagd. Default match is
G603 (USB 046d:406c, Lightspeed 046d:c539, Bluetooth 046d:b01c).

udev starts reset-piper-profile.service on plug-in. apply retries briefly
so ratbagd can see the device after the udev event.

Env:
  PIPER_PROFILE          Profile index (default 0)
  PIPER_DEVICE_MATCH     Comma-separated name/id needles (default G603)
  PIPER_ATTEMPTS         ratbagd settle retries (default 12)
  PIPER_RETRY_SLEEP      Seconds between retries (default 0.5)
EOF
}

trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

notify() {
    local msg="$1"
    printf '%s\n' "$msg"
    [[ "$QUIET" == "1" ]] && return 0
    if command -v hyprctl >/dev/null 2>&1; then
        hyprctl notify -1 2500 "rgb(305cde)" "$msg" >/dev/null 2>&1 || true
    fi
}

need_ratbag() {
    if ! command -v ratbagctl >/dev/null 2>&1; then
        printf 'ratbagctl not found (install piper / ratbagd)\n' >&2
        return 1
    fi
}

match_device() {
    local id="$1" name="$2" needle raw
    raw="${MATCH//,/ }"
    # shellcheck disable=SC2086
    set -- $raw
    for needle in "$@"; do
        needle="$(trim "$needle")"
        [[ -n "$needle" ]] || continue
        needle="${needle,,}"
        if [[ "${id,,}" == *"$needle"* || "${name,,}" == *"$needle"* ]]; then
            return 0
        fi
    done
    return 1
}

list_devices() {
    ratbagctl list 2>/dev/null || true
}

each_match() {
    local line id name
    while IFS= read -r line || [[ -n "${line:-}" ]]; do
        [[ -n "$line" ]] || continue
        [[ "$line" == *:* ]] || continue
        id="$(trim "${line%%:*}")"
        name="$(trim "${line#*:}")"
        [[ -n "$id" ]] || continue
        if match_device "$id" "$name"; then
            printf '%s\t%s\n' "$id" "$name"
        fi
    done < <(list_devices)
}

apply_one() {
    local id="$1" name="$2" current
    current="$(ratbagctl "$id" profile active get 2>/dev/null || true)"
    current="$(trim "$current")"
    if [[ "$current" == "$PROFILE" ]]; then
        printf '%s (%s): already profile %s\n' "$name" "$id" "$PROFILE"
        return 0
    fi
    if ! ratbagctl "$id" profile active set "$PROFILE" >/dev/null; then
        printf 'failed to set %s (%s) to profile %s\n' "$name" "$id" "$PROFILE" >&2
        return 1
    fi
    notify "Piper: ${name} -> profile ${PROFILE}"
}

apply_profile() {
    local attempt=1 pairs id name found=0 ok=0
    need_ratbag || return 1
    mkdir -p "$STATE_DIR"

    while ((attempt <= ATTEMPTS)); do
        pairs="$(each_match || true)"
        if [[ -n "$pairs" ]]; then
            while IFS=$'\t' read -r id name || [[ -n "${id:-}" ]]; do
                [[ -n "$id" ]] || continue
                found=1
                if apply_one "$id" "$name"; then
                    ok=1
                fi
            done <<<"$pairs"
            if [[ "$ok" -eq 1 ]]; then
                return 0
            fi
        fi
        sleep "$RETRY_SLEEP"
        attempt=$((attempt + 1))
    done

    if [[ "$found" -eq 0 ]]; then
        printf 'no ratbag device matching %s\n' "$MATCH"
        return 0
    fi
    return 1
}

show_status() {
    need_ratbag || return 1
    local id name current
    printf 'match=%s profile=%s\n' "$MATCH" "$PROFILE"
    if [[ -z "$(list_devices)" ]]; then
        printf 'ratbagctl list: (no devices)\n'
        return 0
    fi
    printf 'ratbagctl list:\n'
    list_devices
    while IFS=$'\t' read -r id name || [[ -n "${id:-}" ]]; do
        [[ -n "$id" ]] || continue
        current="$(ratbagctl "$id" profile active get 2>/dev/null || printf '?')"
        printf 'active %s (%s): %s\n' "$name" "$id" "$(trim "$current")"
    done < <(each_match)
}

with_lock() {
    mkdir -p "$STATE_DIR"
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        printf 'reset-piper-profile already running\n'
        return 0
    fi
    "$@"
}

cmd="${1:-apply}"
case "$cmd" in
    apply | reset | "")
        with_lock apply_profile
        ;;
    status)
        show_status
        ;;
    -h | --help | help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
