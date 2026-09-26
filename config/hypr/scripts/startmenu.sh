#!/usr/bin/env bash

export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_DATA_DIRS="${XDG_DATA_HOME}:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

# Foreground so qs-startmenu.service can Restart=. systemd is the
# singleton; do not pass -d or -n ( -n plus Restart= would tight-loop).
exec qs -c startmenu
