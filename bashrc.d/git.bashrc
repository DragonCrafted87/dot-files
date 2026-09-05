#!/usr/bin/env bash

DEPTH_TO_SEARCH=3

alias pre-commit-update='pre-commit autoupdate'

function git-delete-tags ()
{
    set -e
    git tag --delete "$1"
    git push --delete origin "$1"
}

function git-push-tags ()
{
    git push origin --tags
}

function git-hold-file ()
{
    git update-index --assume-unchanged "$1"
}

function git-release-file ()
{
    git update-index --no-assume-unchanged "$1"
}

function git-status-all-repos ()
{
    find . -maxdepth $DEPTH_TO_SEARCH -name .git -type d -execdir sh -c '
           basename -s .git `git config --get remote.origin.url`;
           git status --short --branch;
    echo "";' -- {} \;
}

function git-pull-all-repos ()
{
    find . -maxdepth $DEPTH_TO_SEARCH -name .git -type d -execdir sh -c '
           basename -s .git `git config --get remote.origin.url`;
           git pull;
    echo "";' -- {} \;
}

function git-push-all-repos ()
{
    find . -maxdepth $DEPTH_TO_SEARCH -name .git -type d -execdir sh -c '
           basename -s .git `git config --get remote.origin.url`;
           git push;
    echo "";' -- {} \;
}

function git-init-all-repos ()
{
    find . -maxdepth $DEPTH_TO_SEARCH -name .git -type d -execdir sh -c '
           basename -s .git `git config --get remote.origin.url`;
           git init;
    echo "";' -- {} \;
}

function git-update-submodules ()
{
    git submodule update --init --recursive
}

function git-check-all-files ()
{
    pre-commit run --all-files
}

function git-convert-master-to-main ()
{
    git branch -m master main
    git fetch origin
    git branch -u origin/main main
    git remote set-head origin -a
}

function git-update-pre-commit-hook ()
{
    local root_dir template hook
    root_dir="$(git rev-parse --show-toplevel)" || return 1
    template="$(git config --get init.templatedir 2>/dev/null || true)"
    template="${template/#\~/$HOME}"
    [[ -n "$template" ]] || template="${HOME}/.config/git/template"
    hook="${template}/hooks/pre-commit"
    if [[ ! -f "$hook" ]]; then
        printf 'missing template hook: %s\n' "$hook" >&2
        return 1
    fi
    install -m 0755 "$hook" "${root_dir}/.git/hooks/pre-commit"
}

function git-clean-branches() {
    # Fetch latest branch info and prune remote branches
    git fetch --prune

    # Get all local branches except current, dev, and release branches
    local branches_to_delete=$(git branch |
        grep -vE '^\*|^\+|dev|release/' |
    sed 's/^[[:space:]]*//')

    if [ -z "$branches_to_delete" ]; then
        echo "No unused branches found to delete"
        return 0
    fi

    echo "The following branches will be deleted:"
    echo "$branches_to_delete"

    # Ask for confirmation
    read -p "Delete these branches? (y/N) " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "$branches_to_delete" | while read -r branch; do
            if [ -n "$branch" ]; then
                git branch -D "$branch"
                echo "Deleted branch: $branch"
            fi
        done
        git gc
        echo "Branch cleanup complete"
    else
        echo "Branch cleanup cancelled"
    fi
}
