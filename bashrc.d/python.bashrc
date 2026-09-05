#!/usr/bin/env bash

alias pylint=pylint_runner

case "$OSTYPE" in
    win*|msys*)
        ;;
    *)
        ;;
esac

# Host-side python-setup moved to setup/modules/install-python-dev.sh
# (workstation / laptop). pre-commit runs in the dotfiles-pre-commit
# container; cache is ~/.cache/pre-commit-docker.

pre-commit-reset-cache() {
    local cache="${PRE_COMMIT_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/pre-commit-docker}"
    printf 'remove %s\n' "$cache"
    rm -rf "$cache"
    mkdir -p "$cache"
}

python-setup() {
    printf 'python-setup is now the workstation module install-python-dev\n' >&2
    printf 'run: update-role\n' >&2
    return 1
}
