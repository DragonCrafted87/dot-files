#!/usr/bin/env bash
# Network mounts for workstation and laptop. Failures are logged and
# ignored so a missing VPN or offline laptop does not fail the user unit.

MOUNTPOINT="${HOME}/Network"
CREDENTIALS="${HOME}/.smbcredentials"
RCLONE_REMOTE="dragon-onedrive"
RCLONE_SHARE="Dragon-OneDrive"

log() {
    printf '%s\n' "$*"
}

is_mounted() {
    local target="$1"
    findmnt -n "$target" >/dev/null 2>&1
}

mount_cifs() {
    local share="$1"
    local target="$2"

    if is_mounted "$target"; then
        log "already mounted: ${target}"
        return 0
    fi

    log "mounting CIFS ${share} -> ${target}"
    if sudo mount -t cifs "$share" "$target" \
        -o credentials="$CREDENTIALS",uid="$(id -u)",gid="$(id -g)",nofail,vers=3.0,iocharset=utf8; then
        log "success: ${target} (CIFS)"
    else
        log "failed: ${target} (CIFS)"
    fi
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
    log "mounting NFS castellan:/srv/data -> ${MOUNTPOINT}/castellan-data"
    if sudo mount -t nfs -o nolock,vers=4,soft,timeo=10,retrans=3 \
        castellan.stealthdragonland.net:/srv/data "${MOUNTPOINT}/castellan-data"; then
        log "success: castellan-data (NFS)"
    else
        log "failed: castellan-data (NFS)"
    fi
fi

log "network mount finished"
exit 0
