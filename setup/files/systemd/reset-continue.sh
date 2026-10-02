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

# network-online.target does not wait on this distro: NetworkManager-wait-online
# is disabled, so the target is reached while mirror names still fail to resolve.
# Spend the wait here. A reboot would just race DNS again and burn an attempt.
wait_for_repo() {
    local repo="$1"
    local limit="${RESET_REPO_WAIT_SECS:-180}"
    local step=2
    local waited=0
    if [[ "$DRY" == 1 ]]; then
        record "wait-repo ${repo}"
        return "${RESET_TEST_REPO_RC:-0}"
    fi
    log_line "waiting up to ${limit}s for ${repo}/setup/role.sh"
    while [[ ! -f "${repo}/setup/role.sh" ]]; do
        if [[ "$waited" -ge "$limit" ]]; then
            log_line "repo not ready at ${repo} after ${waited}s"
            return 1
        fi
        if [[ $((waited % 10)) -eq 0 ]]; then
            log_line "repo not ready at ${repo} (${waited}s)"
        fi
        sleep "$step"
        waited=$((waited + step))
    done
    log_line "repo ready at ${repo} after ${waited}s"
}

wait_for_install_dns() {
    local host="${RESET_MIRROR_HOST:-mirror.openmandriva.org}"
    local limit="${RESET_DNS_WAIT_SECS:-300}"
    local step=5
    local waited=0
    if [[ "$DRY" == 1 ]]; then
        record "wait-dns ${host}"
        return "${RESET_TEST_DNS_RC:-0}"
    fi
    if [[ -x /usr/bin/nm-online ]]; then
        log_line "waiting for NetworkManager before ${host}"
        NM_ONLINE_TIMEOUT=60 /usr/bin/nm-online -s -q \
            || log_line "NetworkManager startup wait ended; still checking DNS"
    fi
    log_line "waiting up to ${limit}s for DNS ${host}"
    while true; do
        if getent hosts "$host" >/dev/null 2>&1; then
            log_line "DNS ready for ${host} after ${waited}s"
            return 0
        fi
        if [[ "$waited" -ge "$limit" ]]; then
            log_line "DNS not ready for ${host} after ${waited}s"
            return 1
        fi
        if [[ $((waited % 15)) -eq 0 ]]; then
            log_line "DNS not ready for ${host} (${waited}s)"
        fi
        sleep "$step"
        waited=$((waited + step))
    done
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
    wait_for_repo "$repo"
    RESET_CONFIRM=yes RESET_FROM_BOOT=1 \
        python3 "${repo}/setup/modules/common/prune-extra-packages.py"
}

run_install() {
    record write-role
    record run-role
    local repo role user home group uid runtime waited
    repo="$(read_trim "${PLAN_DIR}/repo")"
    role="$(read_trim "${PLAN_DIR}/role")"
    user="$(read_trim "${PLAN_DIR}/user")"
    if [[ "$DRY" != 1 ]]; then
        wait_for_repo "$repo"
    fi
    home="$(getent passwd "$user" | cut -d: -f6)"
    uid="$(id -u "$user")"
    [[ -n "$home" && -n "$uid" ]] || return 1
    runtime="/run/user/${uid}"
    # Recorded in dry-run too. Linger at role-install time is too late:
    # the user bus has to exist before role.sh's systemctl --user calls.
    record "start-user-session XDG_RUNTIME_DIR=${runtime} DOTFILES_HOME=${home}"
    if [[ "$DRY" == 1 ]]; then
        # false must be a simple command. set -e ignores a failure inside
        # if/&&/||, which would hide this test switch.
        if [[ "${RESET_TEST_EARLY_FAIL:-0}" != 1 ]]; then
            return "${RESET_TEST_INSTALL_RC:-0}"
        fi
        false
        return "${RESET_TEST_INSTALL_RC:-0}"
    fi
    [[ -d "$home" ]] || return 1
    group="$(id -g "$user")"
    install -d -o "$user" -g "$group" "${home}/.config/dot-files"
    install -m 0644 -o "$user" -g "$group" "${PLAN_DIR}/role" "${home}/.config/dot-files/role"
    install -m 0644 -o "$user" -g "$group" "${PLAN_DIR}/subroles" "${home}/.config/dot-files/subroles"
    loginctl enable-linger "$user"
    systemctl start "user@${uid}.service"
    waited=0
    while [[ ! -S "${runtime}/bus" ]]; do
        if [[ "$waited" -ge 30 ]]; then
            return 1
        fi
        sleep 1
        waited=$((waited + 1))
    done
    sudo -u "$user" -H env \
        HOME="$home" \
        USER="$user" \
        LOGNAME="$user" \
        XDG_RUNTIME_DIR="$runtime" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=${runtime}/bus" \
        DOTFILES_USER="$user" \
        DOTFILES_HOME="$home" \
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
        remove)
            set +e
            (
                set -e
                wait_for_install_dns
                run_remove
            )
            rc=$?
            set -e
            ;;
        install)
            set +e
            (
                set -e
                wait_for_install_dns
                run_install
            )
            rc=$?
            set -e
            ;;
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
