---
name: commit-hooks
description: Use when editing Python, shell, or Markdown in this repo, or when a pre-commit hook fails.
---

# Commit hooks

The Docker wrapper comes from `install-python-dev`. Hook config lives
in `config/git/template`. CI is `.github/workflows/pre-commit.yml`.

## Checks

Python uses black, isort with one import per line, flake8 at column
120, and pylint with `.pylintrc`. An f-string is the form pylint C0209
expects.

A hyphenated module name fails pylint C0103. When the filename has to
stay hyphenated, disable that check on the first line.

Bash uses beautysh with indent 4 and shellcheck at error severity.
Markdown uses mdformat and markdownlint. A skill file starts with YAML
front matter, and the mdformat hook keeps that block.

A file with a shebang is executable, and an executable file has a
shebang. A Hyprland `exec` line that calls `python3 file.py` stays off
that pair.

`.scratch/` is outside the hooks.

## Run

```bash
pre-commit run
pre-commit run --all-files
```
