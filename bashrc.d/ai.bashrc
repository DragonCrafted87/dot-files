#!/usr/bin/env bash
# AI helpers (dictation, Grok CLI).

export SUPERPOWERS_DISABLE_TELEMETRY=1
export DISABLE_TELEMETRY=1
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

export PATH="$HOME/.grok/bin:$PATH"
if [[ -r "$HOME/.grok/completions/bash/grok.bash" ]]; then
    # shellcheck disable=SC1091
    source "$HOME/.grok/completions/bash/grok.bash"
fi

function ai-dictate ()
{
    python -I ~/dot-files/scripts/dictation.py
}
