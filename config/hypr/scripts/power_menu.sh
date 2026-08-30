#!/bin/sh

power_menu="Lock\nLogout\nReboot\nShutdown\nSuspend"

choice=$(echo -e "$power_menu" | rofi -dmenu -i \
  -p "Power" \
  -theme-str 'window { width: 28%; } listview { lines: 7; }' \
  -no-custom)

case "$choice" in
    "Lock") hyprlock & ;;
    "Logout") hyprctl dispatch exit ;;
    "Reboot") systemctl reboot ;;
    "Shutdown") systemctl poweroff ;;
    "Suspend") systemctl suspend ;;
esac
