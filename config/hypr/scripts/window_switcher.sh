#!/bin/sh

# Get ALL windows (normal + minimized/special) sorted by executable
windows=$(hyprctl clients -j | jq -r '
  .[] | 
  "\(.initialClass // .class) | \(.title) | \(.workspace.name) | \(.address)"
' | sort -f -t '|' -k1)

selected=$(echo "$windows" | rofi -dmenu -i \
  -p "Restore One Window" \
  -show-icons \
  -theme-str 'window { width: 92%; } listview { lines: 22; }' \
  -markup-rows)

if [ -n "$selected" ]; then
    address=$(echo "$selected" | grep -o '0x[0-9a-f]*$')
    
    # Get the real normal workspace (even if special is currently shown)
    target_ws=$(hyprctl monitors -j | jq -r '.[0].activeWorkspace.id')
    
    # Move window to the normal workspace + focus + hide special
    hyprctl --batch "
        dispatch movetoworkspacesilent $target_ws,address:$address;
        dispatch focuswindow address:$address;
        dispatch togglespecialworkspace minimized
    " > /dev/null 2>&1
    
    # Extra safety delay + re-hide if still visible
    sleep 0.08
    current_special=$(hyprctl monitors -j | jq -r '.[0].specialWorkspace.name // ""')
    if [[ "$current_special" == *"minimized"* ]]; then
        hyprctl dispatch togglespecialworkspace minimized
    fi
fi