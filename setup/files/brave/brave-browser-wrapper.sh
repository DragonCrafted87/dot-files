#!/usr/bin/env bash
# User-PATH wrapper. OM /usr/bin/brave-browser ignores brave-flags.conf.
set -euo pipefail

flags_file="${XDG_CONFIG_HOME:-$HOME/.config}/brave-flags.conf"
declared=()
if [[ -f "$flags_file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        declared+=("$line")
    done <"$flags_file"
fi

real=""
for candidate in /usr/lib64/brave-browser/brave /usr/lib/brave-browser/brave /opt/brave.com/brave/brave; do
    if [[ -x "$candidate" ]]; then
        real="$candidate"
        break
    fi
done
if [[ -z "$real" ]]; then
    # Fall back to the packaged wrapper, but drop this dir from PATH so
    # we do not recurse into ourselves.
    PATH="${PATH//:${HOME}\/.local\/bin/}"
    PATH="${PATH//${HOME}\/.local\/bin:/}"
    real="$(command -v brave-browser || true)"
fi
if [[ -z "$real" ]]; then
    echo "brave-browser wrapper: no Brave binary found" >&2
    exit 127
fi

exec "$real" "${declared[@]}" "$@"
