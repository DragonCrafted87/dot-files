#!/bin/bash

export GIT_BASH=true

for file in "$HOME"/dot-files/bashrc.d/*.bashrc;
do
    # shellcheck disable=SC1090
    source "$file"
done

eval "$(oh-my-posh init bash --config "${DOTFILES_ROOT:-$HOME/dot-files}/omp.yaml")"
