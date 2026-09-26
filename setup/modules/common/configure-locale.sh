#!/usr/bin/env bash
# Install the same /etc/locale.conf on every role.
# LC_COLLATE=C: byte order for ls/sort/globs (dotfiles first).
# LC_TIME=en_DK.UTF-8: ISO-8601 timestamps.

set -euo pipefail
# shellcheck disable=SC1091
. "${REPO_ROOT:-$DOTFILES_ROOT}/setup/lib/lib.sh"

require_user

SRC_LOCALE="${SETUP_FILES_DIR}/locale/locale.conf"
SRC_PLASMA="${SETUP_FILES_DIR}/locale/plasma-localerc"
DEST_LOCALE="/etc/locale.conf"
DEST_PLASMA="${CONFIG_TARGET_DIR}/plasma-localerc"

[[ -f "$SRC_LOCALE" ]] || die "missing ${SRC_LOCALE}"
[[ -f "$SRC_PLASMA" ]] || die "missing ${SRC_PLASMA}"

normalize_locale() {
    local value="${1:-}"
    value="${value//\"/}"
    value="${value,,}"
    value="${value/.utf-8/.utf8}"
    printf '%s' "$value"
}

locale_is_available() {
    local want loc
    want="$(normalize_locale "$1")"
    [[ -n "$want" ]] || return 1
    while IFS= read -r loc; do
        if [[ "$(normalize_locale "$loc")" == "$want" ]]; then
            return 0
        fi
    done < <(locale -a)
    return 1
}

ensure_locale_available() {
    local name="$1"
    local ident="${name%%.*}"

    case "$(normalize_locale "$name")" in
        "" | c | c.utf8 | posix) return 0 ;;
    esac
    if locale_is_available "$name"; then
        return 0
    fi

    if ! rpm -q locales-en >/dev/null 2>&1; then
        ensure_packages locales-en
    fi
    if locale_is_available "$name"; then
        return 0
    fi

    log "generate locale ${name}"
    run sudo localedef -c -i "$ident" -f UTF-8 "$name"
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        return 0
    fi
    locale_is_available "$name" || die "locale ${name} is not available after localedef"
}

ensure_locales_from_file() {
    local file="$1"
    local line value
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" == *=* ]] || continue
        value="${line#*=}"
        ensure_locale_available "$value"
    done <"$file"
}

install_root_file() {
    local src="$1"
    local dest="$2"
    if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
        return 0
    fi
    log "write ${dest}"
    run sudo install -m 0644 "$src" "$dest"
}

install_user_file() {
    local src="$1"
    local dest="$2"
    if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
        return 0
    fi
    log "write ${dest}"
    run install -m 0644 "$src" "$dest"
}

ensure_locales_from_file "$SRC_LOCALE"
install_root_file "$SRC_LOCALE" "$DEST_LOCALE"
install_user_file "$SRC_PLASMA" "$DEST_PLASMA"
