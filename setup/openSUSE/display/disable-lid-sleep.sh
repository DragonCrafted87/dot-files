#!/bin/bash
# Script to disable sleep on lid close in openSUSE Leap 15.6

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Use sudo."
    exit 1
fi

# Path to logind.conf
CONFIG_FILE="/etc/systemd/logind.conf"

# Backup and update logind.conf
if [ ! -f "${CONFIG_FILE}.bak" ]; then
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    echo "Backed up $CONFIG_FILE to ${CONFIG_FILE}.bak"
fi

cat > "$CONFIG_FILE" << EOF
[Login]
HandleLidSwitch=ignore
HandleLidSwitchDocked=ignore
HandleLidSwitchExternalPower=ignore
EOF

# Restart systemd-logind
systemctl restart systemd-logind
echo "Applied systemd-logind settings."

# Check for acpid
if systemctl is-active --quiet acpid; then
    echo "acpid is running, checking lid event configuration..."
    if [ -f /etc/acpi/events/lid ]; then
        mv /etc/acpi/events/lid /etc/acpi/events/lid.bak
        echo "Moved /etc/acpi/events/lid to /etc/acpi/events/lid.bak"
        systemctl restart acpid
    else
        echo "No lid event file found in /etc/acpi/events/"
    fi
else
    echo "acpid is not running."
fi

# Optional: Add kernel parameter (commented out, uncomment if needed)
# GRUB_FILE="/etc/default/grub"
# if ! grep -q "button.lid_init_state=open" "$GRUB_FILE"; then
#     sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="button.lid_init_state=open /' "$GRUB_FILE"
#     grub2-mkconfig -o /boot/grub2/grub.cfg
#     echo "Added kernel parameter. Reboot required."
# fi

echo "Lid sleep disabled. Close the lid to test."
echo "Monitor logs with: journalctl -u systemd-logind -n 100 -f"
