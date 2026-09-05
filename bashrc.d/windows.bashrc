#!/usr/bin/env bash

case "$OSTYPE" in
    win*|msys*|cygwin*)
        ;;
    *)
        return
        ;;
esac
USER=$(whoami)

EXPLORER_CACHE_DIR="${LOCALAPPDATA:-/c/Users/${USER}/AppData/Local}/Microsoft/Windows/Explorer"
WINDOWS_PACKAGES_SCRIPT="${PATH_BASH_SETTINGS:-$HOME/dot-files}/windows/install-packages.ps1"

windows-packages-winpath() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$WINDOWS_PACKAGES_SCRIPT"
    else
        printf '%s\n' "$WINDOWS_PACKAGES_SCRIPT"
    fi
}

windows-packages() {
    local role="${1:-personal}"
    shift || true
    MSYS_NO_PATHCONV=1 powershell.exe -NoProfile -ExecutionPolicy Bypass \
        -File "$(windows-packages-winpath)" -Role "$role" "$@"
}

function msys-shutdown ()
{
    taskkill.exe //f //FI "MODULES eq msys-2.0.dll"
}

function windows-clear-icon-cache ()
{
    saved_dir=$PWD
    taskkill.exe //f //im explorer.exe
    cd "$EXPLORER_CACHE_DIR" || return
    rm iconcache_*
    start explorer
    cd "$saved_dir" || return
}

function windows-clear-thumbnail-cache ()
{
    saved_dir=$PWD
    taskkill.exe //f //im explorer.exe
    cd "$EXPLORER_CACHE_DIR" || return
    rm thumbcache_*
    start explorer
    cd "$saved_dir" || return
}

function winget-upgrade-packages ()
{
    windows-packages "${1:-personal}" -Upgrade
}

function winget-install-packages ()
{
    windows-packages "${1:-personal}"
}

function worldographer ()
{
    local java="/c/Program Files/BellSoft/LibericaJDK-17-Full/bin/java.exe"
    local jar="/d/git-home/bin/worldographer/worldographer-1.68.jar"
    if [[ ! -x "$java" || ! -f "$jar" ]]; then
        printf 'worldographer is only set up on the personal Windows box\n' >&2
        return 1
    fi
    "$java" \
        --module-path "/c/Program Files/BellSoft/LibericaJDK-17-Full/jmods" \
        --add-modules javafx.controls,javafx.web,javafx.swing,javafx.graphics,javafx.fxml \
        -Xms12G \
        -Xmx12G \
        -jar "$jar"
}
