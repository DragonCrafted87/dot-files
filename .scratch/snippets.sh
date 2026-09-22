#!/usr/bin/env bash
# shellcheck disable=SC2317
return

find . -type f \( -name "*.sh" -o -name "*.bashrc" \) -exec chmod +x {} +
find . -type f \( -name "*.sh" -o -name "*.bashrc" \) -exec git add --chmod=+x {} +

git commit -m "fix pre-commit issues"

update-dot-files && update-role

sudo rm -rf /opt/hyprland-0.56.2 && rm -rf ~/.cache/hyprland-source && ~/dot-files/setup/modules/install-hyprland-source.sh
~/dot-files/setup/modules/install-hyprland-source.sh
