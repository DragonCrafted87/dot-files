#!/usr/bin/env bash
# Wrapper so systemd / exec-once / keybinds can call the astronomy wallpaper
# helper without depending on the executable bit of the Python file.
set -euo pipefail
exec python3 "${HOME}/.config/hypr/scripts/astro-wallpaper.py" "${@:-apply}"
