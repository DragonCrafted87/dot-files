#!/bin/bash

# shellcheck disable=SC1091
source /etc/profile

for file in ~/.bashrc.d/*.bashrc;
do
    # shellcheck disable=SC1090
    source "$file"
done

eval "$(oh-my-posh init bash --config "${DOTFILES_ROOT:-$HOME/dot-files}/omp.yaml")"
