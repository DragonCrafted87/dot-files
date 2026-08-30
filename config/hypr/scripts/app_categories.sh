#!/bin/bash
# ~/.config/hypr/scripts/app_categories.sh

# Uses whatever theme you already have configured for rofi
ROFI_OPTS="-dmenu -i -p Applications -show-icons -no-custom"

# Categories (display name → FreeDesktop category filter)
declare -A cats=(
    ["All Applications"]=""
    ["Accessories"]="Utility,Accessories"
    ["Development"]="Development"
    ["Education"]="Education"
    ["Games"]="Game"
    ["Graphics"]="Graphics"
    ["Internet"]="Network"
    ["Multimedia"]="AudioVideo,Audio,Video"
    ["Office"]="Office"
    ["Settings"]="Settings,System"
    ["System"]="System"
)

menu=""
for name in "${!cats[@]}"; do
    menu+="$name\n"
done

choice=$(echo -e "$menu" | sort | rofi $ROFI_OPTS)

[[ -z "$choice" ]] && exit 0

filter="${cats[$choice]}"

if [[ -z "$filter" ]]; then
    rofi -show drun -show-icons
else
    rofi -show drun -show-icons -drun-categories "$filter" -display-drun "$choice"
fi
