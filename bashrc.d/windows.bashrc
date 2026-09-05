#!/usr/bin/env bash

case "$OSTYPE" in
    win*|msys*|cygwin*)
        ;;
    *)
        return
        ;;
esac
USER=$(whoami)

WINGET_PACKAGE_LIST=( \
        "7zip.7zip" \
        "Brave.Brave" \
        "CrystalDewWorld.CrystalDiskInfo" \
        "CrystalDewWorld.CrystalDiskMark" \
        "File-New-Project.EarTrumpet" \
        "Foxit.FoxitReader" \
        "JAMSoftware.TreeSize.Free" \
        "Klocman.BulkCrapUninstaller" \
        "Logitech.GHUB" \
        "Microsoft.VisualStudioCode" \
        "OBSProject.OBSStudio" \
        "Piriform.Speccy" \
        "Python.Python.3.12"
    )

WINGET_INSTALL_LIST=( \
    )

function msys-shutdown ()
{
    taskkill.exe //f //FI "MODULES eq msys-2.0.dll"
}

function windows-clear-icon-cache ()
{
    saved_dir=$PWD
    taskkill.exe //f //im explorer.exe
    cd /c/Users/gudem/AppData/Local/Microsoft/Windows/Explorer/ || return
    rm iconcache_*
    start explorer
    cd "$saved_dir" || return
}

function windows-clear-thumbnail-cache ()
{
    saved_dir=$PWD
    taskkill.exe //f //im explorer.exe
    cd /c/Users/gudem/AppData/Local/Microsoft/Windows/Explorer/ || return
    rm thumbcache_*
    start explorer
    cd "$saved_dir" || return
}

function winget-upgrade-packages ()
{
    for i in "${WINGET_PACKAGE_LIST[@]}"
    do
        winget upgrade "$i" -e --source winget
    done
}

function winget-install-packages ()
{
    for i in "${WINGET_INSTALL_LIST[@]}"
    do
        winget install "$i" -e --source winget
    done
}
