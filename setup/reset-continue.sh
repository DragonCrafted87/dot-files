#!/usr/bin/env bash
# Continue a scheduled role reset across boots. Installed as a system unit.
set -euo pipefail

PLAN_DIR="${RESET_PLAN_DIR:-/var/lib/dot-files/reset-plan}"
LOG_FILE="${RESET_LOG:-/var/log/dot-files-reset.log}"
DRY="${RESET_CONTINUE_DRY_RUN:-0}"
ACTION_LOG="${RESET_ACTION_LOG:-}"

log_line() {
    printf '==> %s\n' "$*"
    if [[ "$DRY" != 1 ]]; then
        printf '%s %s\n' "$(date -Is)" "$*" >>"$LOG_FILE" || true
    fi
}

record() {
    printf '%s\n' "$1"
    if [[ -n "$ACTION_LOG" ]]; then
        printf '%s\n' "$1" >>"$ACTION_LOG"
    fi
}

read_trim() {
    tr -d '[:space:]' <"$1"
}

write_trim() {
    printf '%s\n' "$2" >"$1"
}

do_reboot() {
    record reboot
    if [[ "$DRY" == 1 ]]; then
        return 0
    fi
    systemctl reboot
}

do_mask_ly() {
    record mask-ly
    if [[ "$DRY" == 1 ]]; then
        return 0
    fi
    systemctl mask ly.service || true
}

do_disable_unit() {
    record disable-unit
    if [[ "$DRY" == 1 ]]; then
        return 0
    fi
    systemctl disable dot-files-reset.service
}

do_unmask_ly() {
    record unmask-ly
    if [[ "$DRY" == 1 ]]; then
        return 0
    fi
    systemctl unmask ly.service || true
}

stop_forever() {
    local which="$1" attempts="$2"
    write_trim "${PLAN_DIR}/phase" stopped
    write_trim "${PLAN_DIR}/stopped-phase" "$which"
    do_mask_ly
    log_line "dot-files reset stopped after ${attempts} failed attempts of phase ${which}"
    log_line "log: ${LOG_FILE}"
    log_line "clear with: role.sh --reset-abort"
}

run_remove() {
    record prune-remove
    if [[ "$DRY" == 1 ]]; then
        return "${RESET_TEST_REMOVE_RC:-0}"
    fi
    local repo
    repo="$(read_trim "${PLAN_DIR}/repo")"
    RESET_CONFIRM=yes RESET_FROM_BOOT=1 \
        python3 "${repo}/setup/modules/common/prune-extra-packages.py"
}

run_install() {
    record write-role
    record run-role
    if [[ "$DRY" == 1 ]]; then
        return "${RESET_TEST_INSTALL_RC:-0}"
    fi
    local repo role user home
    repo="$(read_trim "${PLAN_DIR}/repo")"
    role="$(read_trim "${PLAN_DIR}/role")"
    user="$(read_trim "${PLAN_DIR}/user")"
    home="$(getent passwd "$user" | cut -d: -f6)"
    [[ -n "$home" && -d "$home" ]] || return 1
    install -d -o "$user" -g "$user" "${home}/.config/dot-files"
    install -m 0644 -o "$user" -g "$user" "${PLAN_DIR}/role" "${home}/.config/dot-files/role"
    install -m 0644 -o "$user" -g "$user" "${PLAN_DIR}/subroles" "${home}/.config/dot-files/subroles"
    sudo -u "$user" -H env HOME="$home" USER="$user" \
        bash "${repo}/setup/role.sh" "$role"
}

finish_install() {
    do_disable_unit
    do_unmask_ly
    record delete-plan
    rm -rf "$PLAN_DIR"
    do_reboot
}

run_attempt() {
    local phase attempts rc=0
    phase="$(read_trim "${PLAN_DIR}/phase")"
    if [[ "$phase" == stopped ]]; then
        do_mask_ly
        log_line "dot-files reset is stopped"
        log_line "log: ${LOG_FILE}"
        log_line "clear with: role.sh --reset-abort"
        return 0
    fi
    attempts="$(read_trim "${PLAN_DIR}/attempts")"
    attempts=$((attempts + 1))
    write_trim "${PLAN_DIR}/attempts" "$attempts"
    if [[ "$attempts" -gt 2 ]]; then
        stop_forever "$phase" "$attempts"
        return 0
    fi
    case "$phase" in
        remove) run_remove || rc=$? ;;
        install) run_install || rc=$? ;;
        *)
            stop_forever "$phase" "$attempts"
            return 0
            ;;
    esac
    if [[ "$rc" -eq 0 ]]; then
        if [[ "$phase" == remove ]]; then
            write_trim "${PLAN_DIR}/phase" install
            write_trim "${PLAN_DIR}/attempts" 0
            do_reboot
        else
            finish_install
        fi
        return 0
    fi
    if [[ "$attempts" -ge 2 ]]; then
        stop_forever "$phase" "$attempts"
    else
        do_reboot
    fi
}

[[ -f "${PLAN_DIR}/phase" ]] || exit 0
run_attempt
