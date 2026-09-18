#!/usr/bin/env bash
# Network mounts for workstation and laptop. Failures are logged and
# ignored so a missing VPN or offline laptop does not fail the user unit.

MOUNTPOINT="${HOME}/Network"
CREDENTIALS="${HOME}/.smbcredentials"
RCLONE_REMOTE="dragon-onedrive"
RCLONE_SHARE="Dragon-OneDrive"
WAIT_SECONDS="${NETWORK_MOUNT_WAIT:-90}"

log() {
    printf '%s\n' "$*"
}

is_mounted() {
    local target="$1"
    findmnt -n "$target" >/dev/null 2>&1
}

cifs_host() {
    local share="$1"
    share="${share#//}"
    printf '%s\n' "${share%%/*}"
}

host_port_ready() {
    local host="$1"
    local port="$2"

    getent hosts "$host" >/dev/null 2>&1 || return 1
    if command -v nc >/dev/null 2>&1; then
        nc -z -w 1 "$host" "$port" >/dev/null 2>&1
        return $?
    fi
    timeout 1 bash -c "echo >/dev/tcp/${host}/${port}" >/dev/null 2>&1
}

wait_for_host_port() {
    local host="$1"
    local port="$2"
    local waited=0

    if host_port_ready "$host" "$port"; then
        return 0
    fi

    log "waiting up to ${WAIT_SECONDS}s for ${host}:${port}"
    while (( waited < WAIT_SECONDS )); do
        sleep 2
        waited=$((waited + 2))
        if host_port_ready "$host" "$port"; then
            log "ready: ${host}:${port} after ${waited}s"
            return 0
        fi
    done
    log "timeout: ${host}:${port} not reachable"
    return 1
}

mount_cifs() {
    local share="$1"
    local target="$2"
    local host
    local attempt

    if is_mounted "$target"; then
        log "already mounted: ${target}"
        return 0
    fi

    host="$(cifs_host "$share")"
    if ! wait_for_host_port "$host" 445; then
        log "failed: ${target} (CIFS host ${host} not ready)"
        return 0
    fi

    for attempt in 1 2 3; do
        log "mounting CIFS ${share} -> ${target} (try ${attempt})"
        if sudo mount -t cifs "$share" "$target" \
            -o credentials="$CREDENTIALS",uid="$(id -u)",gid="$(id -g)",nofail,vers=3.0,iocharset=utf8; then
            log "success: ${target} (CIFS)"
            return 0
        fi
        sleep $((attempt * 2))
    done
    log "failed: ${target} (CIFS)"
}

mount_rclone() {
    local target="$1"

    if is_mounted "$target"; then
        log "already mounted: ${target}"
        return 0
    fi

    if [ "$(ls -A "$target" 2>/dev/null)" ]; then
        log "warning: ${target} is not empty, skipping rclone mount"
        return 0
    fi

    log "mounting rclone ${RCLONE_REMOTE}:${RCLONE_SHARE} -> ${target}"
    if rclone mount "${RCLONE_REMOTE}:${RCLONE_SHARE}" "$target" \
        --vfs-cache-mode full \
        --vfs-cache-max-age 1m \
        --vfs-write-back 5s \
        --daemon; then
        sleep 1
        if is_mounted "$target"; then
            log "success: ${target} (rclone)"
        else
            log "failed: ${target} (rclone started but not mounted)"
        fi
    else
        log "failed: ${target} (rclone)"
    fi
}

log "network mount start"
mkdir -p "${MOUNTPOINT}/Dragon-OneDrive" \
    "${MOUNTPOINT}/Storage" \
    "${MOUNTPOINT}/Unrestricted" \
    "${MOUNTPOINT}/Backups" \
    "${MOUNTPOINT}/castellan-data"

mount_rclone "${MOUNTPOINT}/Dragon-OneDrive"
mount_cifs //calligraphy-wyrm.stealthdragonland.net/Storage      "${MOUNTPOINT}/Storage"
mount_cifs //calligraphy-wyrm.stealthdragonland.net/Unrestricted "${MOUNTPOINT}/Unrestricted"
mount_cifs //calligraphy-wyrm.stealthdragonland.net/Backups      "${MOUNTPOINT}/Backups"

if is_mounted "${MOUNTPOINT}/castellan-data"; then
    log "already mounted: ${MOUNTPOINT}/castellan-data"
else
    if wait_for_host_port castellan.stealthdragonland.net 2049; then
        log "mounting NFS castellan:/srv/data -> ${MOUNTPOINT}/castellan-data"
        if sudo mount -t nfs -o nolock,vers=4,soft,timeo=10,retrans=3 \
            castellan.stealthdragonland.net:/srv/data "${MOUNTPOINT}/castellan-data"; then
            log "success: castellan-data (NFS)"
        else
            log "failed: castellan-data (NFS)"
        fi
    else
        log "failed: castellan-data (NFS host not ready)"
    fi
fi

log "network mount finished"
exit 0
