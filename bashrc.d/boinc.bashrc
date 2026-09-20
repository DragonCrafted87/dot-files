#!/usr/bin/env bash
# Terminal helper. ~/bin/boincmgr is first on PATH after a role run;
# this function covers shells that have not picked up that wrapper yet.
boincmgr() {
    if [[ -x "${HOME}/bin/boincmgr" ]]; then
        "${HOME}/bin/boincmgr" "$@"
        return
    fi
    command boincmgr --datadir "${HOME}/.local/share/boinc" "$@"
}
