#!/usr/bin/env bash

alias pylint=pylint_runner

case "$OSTYPE" in
    win*|msys*)
        ;;
    *)
        ;;
esac

# pre-commit runs in the dotfiles-pre-commit container.
# Cache: ~/.cache/pre-commit-docker

pre-commit-reset-cache() {
    local cache="${PRE_COMMIT_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/pre-commit-docker}"
    printf 'remove %s\n' "$cache"
    rm -rf "$cache"
    mkdir -p "$cache"
}
