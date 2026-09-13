#!/usr/bin/env bash
# When a VS Code integrated terminal starts, source a project bashrc if the
# workspace repo has one at the root or under .devcontainer.

vscode-workspace-root() {
    local start dir
    start="${1:-${VSCODE_CWD:-$PWD}}"
    if command -v git >/dev/null 2>&1; then
        dir="$(git -C "$start" rev-parse --show-toplevel 2>/dev/null)" || true
        if [[ -n "$dir" ]]; then
            printf '%s\n' "$dir"
            return 0
        fi
    fi
    if [[ -n "$start" && -d "$start" ]]; then
        printf '%s\n' "$start"
        return 0
    fi
    return 1
}

vscode-source-workspace-bashrc() {
    [[ "${TERM_PROGRAM:-}" == "vscode" ]] || return 0
    [[ "$-" == *i* ]] || return 0

    local root candidate sourced=0
    root="$(vscode-workspace-root)" || return 0

    # Never treat $HOME as a project repo just because a terminal opened there.
    [[ "$root" != "$HOME" ]] || return 0

    if [[ "${VSCODE_WORKSPACE_BASHRC_SOURCED:-}" == "$root" ]]; then
        return 0
    fi

    for candidate in \
        "${root}/.devcontainer/bashrc" \
        "${root}/.devcontainer/.bashrc" \
        "${root}/bashrc" \
        "${root}/.bashrc"
    do
        [[ -f "$candidate" && -r "$candidate" ]] || continue
        # Skip the user login bashrc if a repo root happens to look like home.
        [[ "$candidate" == "${HOME}/.bashrc" ]] && continue
        # shellcheck disable=SC1090
        source "$candidate"
        sourced=1
    done

    if [[ "$sourced" -eq 1 ]]; then
        export VSCODE_WORKSPACE_BASHRC_SOURCED="$root"
    fi
}

vscode-source-workspace-bashrc
