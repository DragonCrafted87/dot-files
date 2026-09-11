#!/usr/bin/env bash
# shellcheck disable=SC2317
return

find . -type f -name "*.sh" -exec chmod +x {} +

git commit -m "fix pre-commit issues"
