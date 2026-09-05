#!/usr/bin/env bash
# Network mounts for workstation and laptop. Failures are logged and
# ignored so a missing VPN or offline laptop does not fail the user unit.

MOUNTPOINT="${HOME}/Network"
CREDENTIALS="${HOME}/.smbcredentials"
RCLONE_REMOTE="dragon-onedrive"
RCLONE_SHARE="Dragon-OneDrive"
