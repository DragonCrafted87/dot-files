#!/usr/bin/env bash

function mc-vpp-command ()
{
    kubectl exec -it -n games "$(kubectl get -n games pod --selector=role=minecraft-vpp -o jsonpath='{.items..metadata.name}')" -- "$@"
}

# shellcheck disable=SC2034,SC2317
function mc-vpp-rcon ()
{
    MCRCON_HOST='192.168.8.3'
    MCRCON_PORT='25575'
    MCRCON_PASS='rcon'

    mcrcon
}

function mc-vpp-logs ()
{
    kubectl logs -n games "$(kubectl get -n games pod --selector=role=minecraft-vpp -o jsonpath='{.items..metadata.name}')" -f
}

function mc-vpp-describe ()
{
    kubectl describe -n games pod "$(kubectl get -n games pod --selector=role=minecraft-vpp -o jsonpath='{.items..metadata.name}')"
}

function mc-vpp-rcon ()
{
    mc-vpp-command mcrcon --password rcon 127.0.0.1
}

function mc-vpp-delete-pod ()
{
    kubectl delete -n games pod "$(kubectl get -n games pod --selector=role=minecraft-vpp -o jsonpath='{.items..metadata.name}')"
}

function mc-redstone-command ()
{
    kubectl exec -it -n games "$(kubectl get -n games pod --selector=role=minecraft-redstone -o jsonpath='{.items..metadata.name}')" -- "$@"
}

function mc-redstone-logs ()
{
    kubectl logs -n games "$(kubectl get -n games pod --selector=role=minecraft-redstone -o jsonpath='{.items..metadata.name}')" -f
}

function mc-redstone-describe ()
{
    kubectl describe -n games pod "$(kubectl get -n games pod --selector=role=minecraft-redstone -o jsonpath='{.items..metadata.name}')"
}

function mc-redstone-rcon ()
{
    mc-redstone-command mcrcon --password rcon 127.0.0.1
}

function mc-redstone-delete-pod ()
{
    kubectl delete -n games pod "$(kubectl get -n games pod --selector=role=minecraft-redstone -o jsonpath='{.items..metadata.name}')"
}

function mc-update-mods ()
{
    if [ -z "$1" ]; then
        MINECRAFT_VERSION='1.19.4'
    else
        MINECRAFT_VERSION="$1"
    fi

    python -I \
        ~/dot-files/scripts/mc_mod_downloader.py \
        ~/dot-files/scripts/mc_modlist.conf \
        'D:/Games/MultiMC/instances/Fabric_Primary/.minecraft' \
        "$MINECRAFT_VERSION"

}
