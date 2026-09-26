#!/usr/bin/env bash
# Pin collation and time format in /etc/locale.conf for every role.
# LC_COLLATE=C: byte order for ls/sort/globs (dotfiles first).
# LC_TIME=en_DK.UTF-8: ISO-8601 timestamps. Other LC_* stay as-is.

set -euo pipefail
# shellcheck disable=SC1091
. "${REPO_ROOT:-$DOTFILES_ROOT}/setup/lib/lib.sh"

require_user

LOCALE_CONF="/etc/locale.conf"
PLASMA_LOCALERC="${CONFIG_TARGET_DIR}/plasma-localerc"

normalize_locale() {
    local value="${1:-}"
    value="${value//\"/}"
    value="${value,,}"
    value="${value/.utf-8/.utf8}"
    printf '%s' "$value"
}

collate_is_byte_order() {
    case "$(normalize_locale "$1")" in
        c | c.utf8 | posix) return 0 ;;
        *) return 1 ;;
    esac
}

time_is_iso() {
    case "$(normalize_locale "$1")" in
        en_dk | en_dk.utf8) return 0 ;;
        *) return 1 ;;
    esac
}

lang_is_c() {
    case "$(normalize_locale "$1")" in
        "" | c | posix) return 0 ;;
        *) return 1 ;;
    esac
}

locale_conf_value() {
    local key="$1"
    local file="$2"
    local line value=""
    [[ -f "$file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "${key}="* ]]; then
            value="${line#*=}"
        fi
    done <"$file"
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

    if locale_is_available "$name"; then
        return 0
    fi
    if [[ "$ident" == "C" || "$ident" == "POSIX" ]]; then
        return 0
    fi

    if rpm -q locales-en >/dev/null 2>&1; then
        log "locales-en already installed"
    else
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

write_locale_conf() {
    local src="$1"
    local dest="$2"
    local lang="$3"
    local collate="$4"
    local time_loc="$5"
    local line
    local seen_lang=0 seen_collate=0 seen_time=0

    : >"$dest"
    if [[ -f "$src" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            case "$line" in
                LANG=*)
                    if [[ "$seen_lang" -eq 1 ]]; then
                        continue
                    fi
                    printf 'LANG=%s\n' "$lang" >>"$dest"
                    seen_lang=1
                    ;;
                LC_COLLATE=*)
                    if [[ "$seen_collate" -eq 1 ]]; then
                        continue
                    fi
                    printf 'LC_COLLATE=%s\n' "$collate" >>"$dest"
                    seen_collate=1
                    ;;
                LC_TIME=*)
                    if [[ "$seen_time" -eq 1 ]]; then
                        continue
                    fi
                    printf 'LC_TIME=%s\n' "$time_loc" >>"$dest"
                    seen_time=1
                    ;;
                *)
                    printf '%s\n' "$line" >>"$dest"
                    ;;
            esac
        done <"$src"
    fi
    if [[ "$seen_lang" -eq 0 ]]; then
        printf 'LANG=%s\n' "$lang" >>"$dest"
    fi
    if [[ "$seen_collate" -eq 0 ]]; then
        printf 'LC_COLLATE=%s\n' "$collate" >>"$dest"
    fi
    if [[ "$seen_time" -eq 0 ]]; then
        printf 'LC_TIME=%s\n' "$time_loc" >>"$dest"
    fi
}

sync_locale_conf() {
    local current_lang current_collate current_time
    local want_collate want_time
    local src_copy out

    current_lang="$(locale_conf_value LANG "$LOCALE_CONF")"
    current_collate="$(locale_conf_value LC_COLLATE "$LOCALE_CONF")"
    current_time="$(locale_conf_value LC_TIME "$LOCALE_CONF")"

    want_lang="$DOTFILES_LANG"
    if [[ -n "$current_lang" ]] && ! lang_is_c "$current_lang"; then
        want_lang="$current_lang"
    fi
    want_collate="$DOTFILES_LC_COLLATE"
    if collate_is_byte_order "$current_collate"; then
        want_collate="$current_collate"
    fi
    want_time="$DOTFILES_LC_TIME"
    if time_is_iso "$current_time"; then
        want_time="$current_time"
    fi

    if [[ -n "$current_lang" ]] &&
        ! lang_is_c "$current_lang" &&
        collate_is_byte_order "$current_collate" &&
        time_is_iso "$current_time"; then
        return 0
    fi

    src_copy="$(mktemp)"
    out="$(mktemp)"
    if [[ -f "$LOCALE_CONF" ]]; then
        cp "$LOCALE_CONF" "$src_copy"
    fi
    write_locale_conf "$src_copy" "$out" "$want_lang" "$want_collate" "$want_time"
    rm -f "$src_copy"

    if [[ -f "$LOCALE_CONF" ]] && cmp -s "$LOCALE_CONF" "$out"; then
        rm -f "$out"
        return 0
    fi

    log "locale LC_COLLATE=${want_collate} LC_TIME=${want_time}"
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        cat "$out"
        rm -f "$out"
        return 0
    fi
    sudo install -m 0644 "$out" "$LOCALE_CONF"
    rm -f "$out"
}

sync_plasma_localerc() {
    local current
    [[ -f "$PLASMA_LOCALERC" ]] || return 0
    current="$(locale_conf_value LC_TIME "$PLASMA_LOCALERC")"
    if time_is_iso "$current"; then
        return 0
    fi
    log "plasma-localerc LC_TIME=${DOTFILES_LC_TIME}"
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        return 0
    fi
    if grep -qE '^LC_TIME=' "$PLASMA_LOCALERC"; then
        sed -i -E "s|^LC_TIME=.*|LC_TIME=${DOTFILES_LC_TIME}|" "$PLASMA_LOCALERC"
    else
        printf 'LC_TIME=%s\n' "$DOTFILES_LC_TIME" >>"$PLASMA_LOCALERC"
    fi
}

ensure_locale_available "$DOTFILES_LC_TIME"
sync_locale_conf
sync_plasma_localerc
