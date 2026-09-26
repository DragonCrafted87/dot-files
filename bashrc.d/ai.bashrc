#!/usr/bin/env bash
# AI helpers (dictation, Grok CLI).

export PATH="$HOME/.grok/bin:$PATH"
if [[ -r "$HOME/.grok/completions/bash/grok.bash" ]]; then
    # shellcheck disable=SC1091
    source "$HOME/.grok/completions/bash/grok.bash"
fi

function ai-dictate ()
{
    python -I ~/dot-files/scripts/dictation.py
}
