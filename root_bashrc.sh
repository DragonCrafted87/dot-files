#!/bin/bash

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
