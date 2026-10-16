#!/usr/bin/env bash
# Vikunja task helpers. Credentials: ~/.config/vikunja/grok-cli.env

function vk-list ()
{
    python -I ~/dot-files/scripts/vikunja.py list "$@"
}

function vk-done ()
{
    # Quoted so beautysh does not read the subcommand as a loop keyword.
    python -I ~/dot-files/scripts/vikunja.py 'done' "$@"
}
