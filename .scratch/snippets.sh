#!/usr/bin/env bash
# shellcheck disable=SC2317
return

find . -type f \( -name "*.sh" -o -name "*.bashrc" \) -exec chmod +x {} +
find . -type f \( -name "*.sh" -o -name "*.bashrc" \) -exec git add --chmod=+x {} +

git commit -m "fix pre-commit issues"
