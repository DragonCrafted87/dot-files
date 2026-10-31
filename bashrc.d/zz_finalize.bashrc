#!/usr/bin/env bash

# Hermes Agent command. Installer line, kept last so a later snippet
# cannot drop ~/.local/bin. 01_base_settings.bashrc adds it first.
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
