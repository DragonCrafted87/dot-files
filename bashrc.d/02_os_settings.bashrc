#!/usr/bin/env bash

OMP_INSTALL_DIR="$HOME/bin"

case "$OSTYPE" in
    linux*)
        [[ -t 1 ]] && echo "Linux"
        # function ubuntu-release-upgrade ()
        # {
        #     echo "Updating"
        #     sudo apt-get update
        #     sudo apt-get upgrade -y
        #     sudo apt-get dist-upgrade -y
        #     echo "Bypass Upgradability Check"
        #     sudo sed -i 's/continue/pass/g' /usr/lib/python3/dist-packages/UpdateManager/Core/MetaRelease.py
        #     echo "Upgrade distro"
        #     sudo do-release-upgrade
        # }

        ;;

    win*|msys*|cygwin*)
        [[ -t 1 ]] && echo "MS Windows"
        BASE_PATH=$PATH
        PATH=$PATH:$BASE_PATH
        PATH="$PATH:/c/Program Files/Docker/Docker/resources/bin/"
        export PATH

        OMP_INSTALL_DIR="$HOME/bin"
        ;;
    *)
        [[ -t 1 ]] && echo "unknown: $OSTYPE"
        ;;
esac
