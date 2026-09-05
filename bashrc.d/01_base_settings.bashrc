#!/usr/bin/env bash

HISTCONTROL='ignoredups:ignorespace:erasedups'
HISTSIZE=1000
HISTFILESIZE=2000
shopt -s checkwinsize
shopt -s histappend

export WHITE='\033[1;37m'
export BLACK='\033[0;30m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export DARK_GRAY='\033[1;30m'
export DARK_YELLOW='\033[0;33m'
export GREEN='\033[0;32m'
export LIGHT_BLUE='\033[1;34m'
export LIGHT_CYAN='\033[1;36m'
export LIGHT_GRAY='\033[0;37m'
export LIGHT_GREEN='\033[1;32m'
export LIGHT_PURPLE='\033[1;35m'
export LIGHT_RED='\033[1;31m'
export LIGHT_YELLOW='\033[1;33m'
export PURPLE='\033[0;35m'
export RED='\033[0;31m'
export NC='\033[0m'

export VISUAL=nano
export EDITOR="$VISUAL"

is_windows() {
    case "${OSTYPE:-}" in
        win* | msys* | cygwin*) return 0 ;;
        *) return 1 ;;
    esac
}

# make less more friendly for non-text input files, see lesspipe(1)
if ! is_windows; then
    [ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"
fi

# Repo root as seen by this sourced file. Works even if the clone is not
# at ~/dot-files, as long as bashrc.d lives inside the repo.
_dotfiles_from_source() {
    local here
    here="$(realpath "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
    here="$(dirname "$here")"
    realpath "${here}/.." 2>/dev/null || printf '%s' "$(cd "${here}/.." && pwd)"
}

DOTFILES_ROOT="${DOTFILES_ROOT:-$(_dotfiles_from_source)}"
export DOTFILES_ROOT
export PATH_BASH_SETTINGS="$DOTFILES_ROOT"

_dotfiles_state_dir="${HOME}/.config/dot-files"
mkdir -p "$_dotfiles_state_dir" 2>/dev/null || true
if [[ -n "$DOTFILES_ROOT" && -d "$DOTFILES_ROOT" ]]; then
    printf '%s\n' "$DOTFILES_ROOT" >"${_dotfiles_state_dir}/root" 2>/dev/null || true
fi
unset -f _dotfiles_from_source
unset _dotfiles_state_dir

export GOPATH=$HOME/go

BASE_PATH=$PATH

PATH=$HOME/bin
PATH=$PATH:$HOME/.local/bin
PATH=$PATH:$HOME/scripts
PATH=$PATH:$DOTFILES_ROOT/scripts
PATH=$PATH:$HOME/bin/ffmpeg/bin
PATH=$PATH:$HOME/bin/mkvtoolnix
if ! is_windows; then
    PATH=$PATH:/usr/local/go/bin
fi
PATH=$PATH:$GOPATH/bin
PATH=$PATH:$BASE_PATH
export PATH

export KUBECONFIG=~/.kube/config

if ! is_windows; then
    # set variable identifying the chroot you work in (used in the prompt below)
    if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
        debian_chroot=$(cat /etc/debian_chroot)
    fi

    # If this is an xterm set the title to user@host:dir
    case "$TERM" in
        xterm*|rxvt*)
            PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
            ;;
        *)
            ;;
    esac

    # enable programmable completion features
    if ! shopt -oq posix; then
        if [ -f /usr/share/bash-completion/bash_completion ]; then
            # shellcheck disable=SC1091
            . /usr/share/bash-completion/bash_completion
        elif [ -f /etc/bash_completion ]; then
            # shellcheck disable=SC1091
            . /etc/bash_completion
        fi
    fi
fi
