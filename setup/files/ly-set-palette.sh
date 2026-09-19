#!/usr/bin/env bash
# Apply the Kitty Tango Dark 16-color palette to the current TTY.
# Used by Ly term_reset_cmd so the greeter matches the session.
printf '%b' '\e]P0000000\e]P1CC0000\e]P24E9A06\e]P3C4A000\e]P43465A4\e]P575507B\e]P606989A\e]P7D3D7CF\e]P8555753\e]P9EF2929\e]PA8AE234\e]PBFCE94F\e]PC729FCF\e]PDAD7FA8\e]PE34E2E2\e]PFEEEEEC\ec'
