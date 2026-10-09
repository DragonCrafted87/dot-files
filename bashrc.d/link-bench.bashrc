#!/usr/bin/env bash

# Direct-cable address for a factory switch at 192.168.1.1.
# 192.168.1.100 is calligraphy-wyrm on the house LAN.

case "${HOSTNAME}" in
    runewyrm*)
        function link-bench {
            local con="Wired connection 1"
            local mode="${1:-}"

            case "${mode}" in
                static | lan) ;;
                *)
                    printf 'usage: link-bench static|lan\n' >&2
                    return 2
                    ;;
            esac

            (
                set -eu
                if [[ "${mode}" == static ]]; then
                    sudo nmcli con modify "${con}" ipv4.addresses 192.168.1.100/24
                    sudo nmcli con modify "${con}" ipv4.gateway 192.168.1.1
                    sudo nmcli con modify "${con}" ipv4.method manual
                else
                    sudo nmcli con modify "${con}" ipv4.method auto
                    sudo nmcli con modify "${con}" ipv4.gateway ""
                    sudo nmcli con modify "${con}" ipv4.addresses ""
                fi
                sudo nmcli con up "${con}"
            )
        }
        ;;
esac
