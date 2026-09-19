#!/usr/bin/env bash
# TUI colors that follow Kitty Tango Dark. Sourced from bashrc.d.

# GREP: red matches, cyan file names, magenta line numbers, green function.
export GREP_COLORS='ms=01;31:mc=01;31:sl=:cx=:fn=01;36:ln=01;35:bn=32:se=36'

# bat uses the terminal ANSI palette when theme is "ansi".
export BAT_THEME="${BAT_THEME:-ansi}"

# less: raw color codes from git/grep/diff.
export LESS='-R'
export LESS_TERMCAP_mb=$'\e[1;31m'
export LESS_TERMCAP_md=$'\e[1;34m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_so=$'\e[30;47m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;32m'
export LESS_TERMCAP_ue=$'\e[0m'
