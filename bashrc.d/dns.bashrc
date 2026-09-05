#!/usr/bin/env bash

function dns-unbound-pods ()
{
    kubectl get -n dns pod --selector=role=unbound -o jsonpath='{.items..metadata.name}'
    echo ""
}

function dns-unbound-command ()
{
    IFS=' ' read -r -a array <<< "$(dns-unbound-pods)"
    for element in "${array[@]}"
    do
        echo "$element"
        kubectl exec -it -n dns "$element" \
            --  "$@"
    done
}

function dns-unbound-describe-pods ()
{
    pods=$(dns-unbound-pods)
    kubectl describe -n dns pod "$pods"
}

function dns-unbound-pod-logs ()
{
    IFS=' ' read -r -a array <<< "$(dns-unbound-pods)"
    for element in "${array[@]}"
    do
        echo "$element"
        kubectl logs -n dns "$element"
        echo
        echo
        echo
    done
}

function dns-unbound-delete-all-pods ()
{
    pods=$(dns-unbound-pods)
    # shellcheck disable=SC2086
    kubectl delete -n dns pod $pods
}


function dns-bind-pods ()
{
    kubectl get -n dns pod --selector=role=bind -o jsonpath='{.items..metadata.name}'
    echo ""
}

function dns-bind-command ()
{
    IFS=' ' read -r -a array <<< "$(dns-bind-pods)"
    for element in "${array[@]}"
    do
        echo "$element"
        kubectl exec -it -n dns "$element" \
            --  "$@"
    done
}

function dns-bind-describe-pods ()
{
    pods=$(dns-bind-pods)
    kubectl describe -n dns pod "$pods"
}

function dns-bind-pod-logs ()
{
    IFS=' ' read -r -a array <<< "$(dns-bind-pods)"
    for element in "${array[@]}"
    do
        echo "$element"
        kubectl logs -n dns "$element"
        echo
        echo
        echo
    done
}

function dns-bind-delete-all-pods ()
{
    pods=$(dns-bind-pods)
    # shellcheck disable=SC2086
    kubectl delete -n dns pod $pods
}
