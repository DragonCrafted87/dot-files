#!/bin/sh

export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_DATA_DIRS="${XDG_DATA_HOME}:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

exec qs -c startmenu -d -n
