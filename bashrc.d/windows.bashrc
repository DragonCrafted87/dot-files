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
WINDOWS_ROLE_FILE="${HOME}/.config/dot-files/windows-role"

windows-packages-winpath() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$WINDOWS_PACKAGES_SCRIPT"
    else
        printf '%s\n' "$WINDOWS_PACKAGES_SCRIPT"
    fi
}

windows-role() {
    if [[ -n "${1:-}" ]]; then
        case "$1" in
            work|personal)
                mkdir -p "$(dirname "$WINDOWS_ROLE_FILE")"
                printf '%s\n' "$1" > "$WINDOWS_ROLE_FILE"
                printf 'saved windows role %s -> %s\n' "$1" "$WINDOWS_ROLE_FILE"
                ;;
            *)
                printf 'windows role must be work or personal\n' >&2
                return 1
                ;;
        esac
        return 0
    fi
    if [[ -f "$WINDOWS_ROLE_FILE" ]]; then
        tr -d '[:space:]' < "$WINDOWS_ROLE_FILE"
        return 0
    fi
    printf 'no windows role saved at %s\n' "$WINDOWS_ROLE_FILE" >&2
    printf 'set one with: windows-role work   or   windows-role personal\n' >&2
    return 1
}

windows-packages() {
    local role=""
    if [[ "${1:-}" == work || "${1:-}" == personal ]]; then
        role="$1"
        shift
    elif [[ -n "${1:-}" && "${1:-}" != -* ]]; then
        printf 'windows role must be work or personal\n' >&2
        return 1
    fi
    if [[ -z "$role" ]]; then
        role=$(windows-role) || return 1
    fi
    printf 'using windows role %s\n' "$role"
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
    windows-packages "$@" -Upgrade
}

function winget-install-packages ()
{
    windows-packages "$@"
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
