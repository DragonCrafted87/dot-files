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
    saved_working_dir="$PWD"
    cd ~/dot-files || return
    git pull
    # shellcheck disable=SC1090
    source ~/.bashrc
    cd "$saved_working_dir" || return
}

eval "$(oh-my-posh init bash --config /home/dragon/dot-files/omp.yaml)"
