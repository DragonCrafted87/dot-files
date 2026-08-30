#!/bin/sh

# System Tray / Quick Settings Submenu
tray_menu="Toggle Waybar\nNetwork Manager\nBluetooth Manager\nAudio Control\nPower Menu"

choice=$(echo -e "$tray_menu" | rofi -dmenu -i -p "System Control" -theme-str 'window { width: 34%; } listview { lines: 8; }' -no-custom)

case "$choice" in
    "Toggle Waybar")
        pkill -USR1 waybar || waybar &
        ;;
    "Network Manager")
        nm-connection-editor &
        ;;
    "Bluetooth Manager")
        blueman-manager &
        ;;
    "Audio Control")
        pavucontrol &
        ;;
    "Power Menu")
        ~/.config/hypr/scripts/power_menu.sh
        ;;
esac 
