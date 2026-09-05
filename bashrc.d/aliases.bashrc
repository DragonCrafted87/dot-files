#!/usr/bin/env bash
# shellcheck disable=SC2016

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    # shellcheck disable=SC2015
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto -lah --block-size=M --group-directories-first '

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
else
    alias ls='ls -lah '
fi

# colored GCC warnings and errors
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'
alias clear='clear; clear; clear '

alias which='command -v '

alias replacecpp='find ${PWD} -name "*.cpp" | xargs perl -pi -e '
alias replaceh='find ${PWD} -name "*.h" | xargs perl -pi -e '

alias ps-parents='ps axo stat,ppid,pid,comm | grep -w defunct'
alias pwsh='powershell'

function base_find ()
{
    FIND_EXCLUDES=' | grep -v "\.git" '
    FIND_EXCLUDES=$FIND_EXCLUDES'| grep -v "\.venv" '
    FIND_EXCLUDES=$FIND_EXCLUDES'| grep -v "\.mypy_cache" '
    FIND_EXCLUDES=$FIND_EXCLUDES'| grep -v MakeFile '
    FIND_EXCLUDES=$FIND_EXCLUDES'| grep -v __pycache__ '
    FIND_EXCLUDES=$FIND_EXCLUDES'| grep -v thirdparty '
    FIND_EXCLUDES=$FIND_EXCLUDES'| grep -v "/build/" '
    GREP_COMMAND='| xargs grep --color=always -s -n "'
    FIND_END='"'
    COMMAND=$1
    COMMAND=$COMMAND$FIND_EXCLUDES
    COMMAND=$COMMAND$GREP_COMMAND
    COMMAND=$COMMAND$2
    COMMAND=$COMMAND$FIND_END
    eval "$COMMAND"
}

function f ()
{
    base_find 'find ${PWD}' "$1"
}

function fcmake ()
{
    base_find 'find ${PWD} -name "CMakeLists.txt"' "$1"
}

function fcode ()
{
    base_find 'find ${PWD} -name "*.c*"' "$1"
}

function ffile ()
{
    COMMAND='find ${PWD} -name "*.h*" -o -name "*.c*" -o -name "*.ui" | grep --color=always -s -n '
    COMMAND=$COMMAND$1
    eval "$COMMAND"
}

function fheader ()
{
    base_find 'find ${PWD} -name "*.h*"' "$1"
}

function fpy ()
{
    base_find 'find ${PWD} -name "*.py"' "$1"
}

function fui ()
{
    base_find 'find ${PWD} -name "*.ui"' "$1"
}

function worldographer ()
{
    /c/Program\ Files/BellSoft/LibericaJDK-17-Full/bin/java.exe \
        --module-path "/c/Program\ Files/BellSoft/LibericaJDK-17-Full/jmods" \
        --add-modules javafx.controls,javafx.web,javafx.swing,javafx.graphics,javafx.fxml \
        -Xms12G \
        -Xmx12G \
        -jar "/d/git-home/bin/worldographer/worldographer-1.68.jar"
}
