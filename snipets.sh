#!/bin/bash
# shellcheck disable=SC2317
return

git clone --single-branch --branch alpine https://github.com/ilpianista/pi-hole.git

find . -type f -name "*.sh" -exec chmod +x {} +
