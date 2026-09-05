#!/bin/bash

# shellcheck disable=SC1091
source /etc/profile

for file in ~/.bashrc.d/*.bashrc;
do
    # shellcheck disable=SC1090
    source "$file"
done

function update-dot-files ()
{
    local repo cwd
    repo="$(dotfiles-root 2>/dev/null || true)"
    repo="${repo:-${DOTFILES_ROOT:-$HOME/dot-files}}"
    cwd="$PWD"
    cd "$repo" || return
    git pull
    # shellcheck disable=SC1090
    source ~/.bashrc
    cd "$cwd" || return
}

eval "$(oh-my-posh init bash --config "${DOTFILES_ROOT:-$HOME/dot-files}/omp.yaml")"
