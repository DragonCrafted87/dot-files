#!/usr/bin/env bash
# Apply a machine role, or schedule a walk-away reset.
#
#   ./setup/role.sh workstation
#   ./setup/role.sh --enable-subrole laptop
#   ./setup/role.sh --reset
#   ./setup/role.sh --reset-abort
#
# --reset previews removals, asks for the role, and schedules a boot
# job. It does not remove packages in this session and does not change
# the saved role files. --force is rejected.
#
# Subroles are saved in ~/.config/dot-files/subroles and re-applied on
# every later role run. They are not derived from the hostname.

set -euo pipefail
if [[ -n "${REPO_ROOT:-}" || -n "${DOTFILES_ROOT:-}" ]]; then
    # shellcheck disable=SC1091
    . "${REPO_ROOT:-$DOTFILES_ROOT}/setup/lib/lib.sh"
else
    # shellcheck disable=SC1091
    . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/lib.sh"
fi

usage() {
    cat >&2 <<EOF
usage: $0 [options] [role]

Roles: workstation, htpc, server
       laptop is a subrole: --enable-subrole laptop

Subroles: $(known_subroles | paste -sd, -)

Options:
  --role NAME              role to apply, or the reset default
  --enable-subrole NAME    save NAME and apply its modules
  --disable-subrole NAME   drop NAME from the saved list
  --list-subroles          print known and enabled subroles
  --reset                  preview removals and schedule a walk-away reset
  --reset-abort            cancel a scheduled, running, or stopped reset
  --force                  error; --reset is the walk-away flow
  --dry-run                print actions without changing the system
  --hostname NAME          set the static hostname
  -h, --help               show this help
EOF
    exit 1
}

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s\n' "$value"
}

confirm_yes() {
    local prompt="$1" answer
    printf '%s [y/N] ' "$prompt" >&2
    IFS= read -r answer || answer=""
    answer="$(trim "$answer")"
    answer="${answer,,}"
    case "$answer" in
        y | yes) return 0 ;;
        *) return 1 ;;
    esac
}

validate_named_subroles() {
    local name
    for name in "${enable_subroles[@]}"; do
        valid_subrole "$name" || die "unknown subrole ${name}"
    done
    for name in "${disable_subroles[@]}"; do
        valid_subrole "$name" || die "unknown subrole ${name}"
    done
}

subrole_wants_enabled() {
    local name="$1" item enabled=0
    if has_subrole "$name"; then
        enabled=1
    fi
    for item in "${enable_subroles[@]}"; do
        if [[ "$item" == "$name" ]]; then
            enabled=1
        fi
    done
    for item in "${disable_subroles[@]}"; do
        if [[ "$item" == "$name" ]]; then
            enabled=0
        fi
    done
    [[ "$enabled" -eq 1 ]]
}

ask_role() {
    local default="$1" answer
    printf 'Role [%s]: ' "$default" >&2
    IFS= read -r answer || answer=""
    answer="$(trim "$answer")"
    answer="${answer,,}"
    if [[ -z "$answer" ]]; then
        printf '%s\n' "$default"
        return 0
    fi
    printf '%s\n' "$answer"
}

ask_subrole() {
    local name="$1" default_label="disabled" answer
    if subrole_wants_enabled "$name"; then
        default_label="enabled"
    fi
    printf 'Subrole %s [%s]: ' "$name" "$default_label" >&2
    IFS= read -r answer || answer=""
    answer="$(trim "$answer")"
    answer="${answer,,}"
    if [[ -z "$answer" ]]; then
        answer="$default_label"
    fi
    case "$answer" in
        enabled) return 0 ;;
        disabled) return 1 ;;
        *) die "subrole ${name} must be enabled or disabled" ;;
    esac
}

show_removal_preview() {
    local prune_sh py preview
    prune_sh="$(find_module prune-extra-packages)"
    py="$(dirname "$prune_sh")/prune-extra-packages.py"
    [[ -f "$py" ]] || die "missing ${py}"
    preview="$(
        env -u RESET_CONFIRM -u RESET_FROM_BOOT DOTFILES_DRY_RUN=0 \
            python3 "$py"
    )"
    printf '%s\n' "The remove boot computes this list again. The role does not change it."
    if [[ "${RESET_SKIP_PAGER:-0}" == 1 || "${DOTFILES_DRY_RUN:-0}" == 1 ]]; then
        printf '%s\n' "$preview"
        return 0
    fi
    printf '%s\n' "$preview" | less
}

print_reboot_plan() {
    local role_name="$1"
    local dest="Ly" joined="(none)"
    shift
    if [[ "$role_name" == server ]]; then
        dest="the console"
    fi
    if [[ "$#" -gt 0 ]]; then
        joined="$*"
    fi
    printf '%s\n' "fresh removal on the next boot"
    printf 'role: %s\n' "$role_name"
    printf 'subroles: %s\n' "$joined"
    printf 'final boot: %s\n' "$dest"
}

remove_plan_dir() {
    local dir="$1"
    [[ -d "$dir" ]] || return 0
    rm -rf "$dir" 2>/dev/null || sudo rm -rf "$dir"
}

write_plan() {
    local plan="$1" role_name="$2" sub_text="" name tmp
    shift 2
    for name in "$@"; do
        sub_text+="${name}"$'\n'
    done
    tmp="$(mktemp -d)"
    printf '%s\n' remove >"${tmp}/phase"
    printf '%s\n' 0 >"${tmp}/attempts"
    printf '%s\n' "$(id -un)" >"${tmp}/user"
    printf '%s\n' "$REPO_ROOT" >"${tmp}/repo"
    printf '%s\n' "$role_name" >"${tmp}/role"
    printf '%s' "$sub_text" >"${tmp}/subroles"
    chmod 0644 "${tmp}/phase" "${tmp}/attempts" "${tmp}/user" \
        "${tmp}/repo" "${tmp}/role" "${tmp}/subroles"
    if [[ "${RESET_SKIP_SYSTEMCTL:-0}" == 1 ]]; then
        mkdir -p "$plan"
        chmod 0755 "$plan"
        install -m 0644 "${tmp}/phase" "${tmp}/attempts" "${tmp}/user" \
            "${tmp}/repo" "${tmp}/role" "${tmp}/subroles" "${plan}/"
    else
        sudo install -d -m 0755 "$plan"
        sudo install -m 0644 "${tmp}/phase" "${tmp}/attempts" "${tmp}/user" \
            "${tmp}/repo" "${tmp}/role" "${tmp}/subroles" "${plan}/"
    fi
    rm -rf "$tmp"
}

install_reset_unit() {
    local continue_sh="${REPO_ROOT}/setup/reset-continue.sh"
    local template="${REPO_ROOT}/setup/files/systemd/dot-files-reset.service.in"
    local raw rendered tmp dest="/etc/systemd/system/dot-files-reset.service"
    [[ -f "$continue_sh" ]] || die "missing ${continue_sh}"
    [[ "$continue_sh" == /* ]] || die "reset-continue path is not absolute"
    [[ -f "$template" ]] || die "missing ${template}"
    raw="$(cat "$template")"
    rendered="${raw//@RESET_CONTINUE@/${continue_sh}}"
    tmp="$(mktemp)"
    printf '%s\n' "$rendered" >"$tmp"
    if ! sudo install -m 0644 "$tmp" "$dest"; then
        rm -f "$tmp"
        return 1
    fi
    rm -f "$tmp"
    if ! sudo systemctl daemon-reload; then
        return 1
    fi
    sudo systemctl enable dot-files-reset.service
}

reset_abort() {
    local plan="${RESET_PLAN_DIR:-/var/lib/dot-files/reset-plan}"
    if [[ ! -d "$plan" ]]; then
        printf '%s\n' "no reset is in progress"
        exit 0
    fi
    if [[ "${RESET_SKIP_SYSTEMCTL:-0}" == 1 ]]; then
        printf '%s\n' "systemctl stop dot-files-reset.service"
        printf '%s\n' "systemctl disable dot-files-reset.service"
        printf '%s\n' "systemctl unmask ly.service"
    else
        # stop is not optional. A running oneshot still reboots after
        # disable. Failure leaves the plan in place and does not unmask.
        sudo systemctl stop dot-files-reset.service
        sudo systemctl disable dot-files-reset.service || true
        sudo systemctl unmask ly.service || true
    fi
    remove_plan_dir "$plan"
    exit 0
}

run_reset() {
    local plan="${RESET_PLAN_DIR:-/var/lib/dot-files/reset-plan}"
    local default_role="" chosen_role="" name
    local -a chosen_subs=()
    local -a known=()

    if [[ "$role" == laptop ]]; then
        die "laptop is a subrole; use --enable-subrole laptop"
    fi
    validate_named_subroles
    if [[ -n "$role" ]]; then
        valid_role "$role" || die "unknown role ${role}"
        default_role="$role"
    else
        default_role="$(read_saved_role || true)"
        [[ -n "$default_role" ]] || die "no role saved; pass --role workstation, htpc, or server"
        valid_role "$default_role" || die "unknown role ${default_role}"
    fi

    if [[ -d "$plan" ]]; then
        die "a reset is already scheduled; role.sh --reset-abort clears it"
    fi

    # known_subroles is collected before any read so prompts keep stdin.
    mapfile -t known < <(known_subroles)

    if [[ "${DOTFILES_DRY_RUN:-0}" == 1 ]]; then
        for name in "${known[@]}"; do
            [[ -n "$name" ]] || continue
            if subrole_wants_enabled "$name"; then
                chosen_subs+=("$name")
            fi
        done
        show_removal_preview
        print_reboot_plan "$default_role" "${chosen_subs[@]}"
        exit 0
    fi

    if [[ ! -t 0 && "${RESET_SKIP_PAGER:-0}" != 1 ]]; then
        die "role.sh --reset needs a terminal"
    fi

    show_removal_preview
    if ! confirm_yes "Approve this removal preview?"; then
        exit 1
    fi

    chosen_role="$(ask_role "$default_role")"
    if [[ "$chosen_role" == laptop ]]; then
        die "laptop is a subrole; use --enable-subrole laptop"
    fi
    valid_role "$chosen_role" || die "unknown role ${chosen_role}"

    for name in "${known[@]}"; do
        [[ -n "$name" ]] || continue
        if ask_subrole "$name"; then
            chosen_subs+=("$name")
        fi
    done

    print_reboot_plan "$chosen_role" "${chosen_subs[@]}"
    if ! confirm_yes "Start now?"; then
        exit 0
    fi

    write_plan "$plan" "$chosen_role" "${chosen_subs[@]}"
    if [[ "${RESET_SKIP_SYSTEMCTL:-0}" != 1 ]]; then
        if ! install_reset_unit; then
            remove_plan_dir "$plan"
            die "failed to enable dot-files-reset.service"
        fi
    fi
    if [[ "${RESET_SKIP_REBOOT:-0}" == 1 ]]; then
        printf '%s\n' "reboot"
    else
        sudo systemctl reboot
    fi
    exit 0
}

role=""
role_flag=""
cli_role=0
do_reset=0
do_abort=0
force=0
list_subroles=0
hostname_arg=""
enable_subroles=()
disable_subroles=()

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --reset | -r)
            do_reset=1
            ;;
        --reset-abort)
            do_abort=1
            ;;
        --force | -f)
            force=1
            ;;
        --dry-run)
            DOTFILES_DRY_RUN=1
            export DOTFILES_DRY_RUN
            ;;
        --hostname)
            [[ "$#" -ge 2 ]] || usage
            hostname_arg="$2"
            shift
            ;;
        --hostname=*)
            hostname_arg="${1#--hostname=}"
            ;;
        --role)
            [[ "$#" -ge 2 ]] || usage
            role_flag="$2"
            shift
            ;;
        --role=*)
            role_flag="${1#--role=}"
            ;;
        --enable-subrole)
            [[ "$#" -ge 2 ]] || usage
            enable_subroles+=("$2")
            shift
            ;;
        --enable-subrole=*)
            enable_subroles+=("${1#--enable-subrole=}")
            ;;
        --disable-subrole)
            [[ "$#" -ge 2 ]] || usage
            disable_subroles+=("$2")
            shift
            ;;
        --disable-subrole=*)
            disable_subroles+=("${1#--disable-subrole=}")
            ;;
        --list-subroles)
            list_subroles=1
            ;;
        -h | --help)
            usage
            ;;
        --)
            shift
            break
            ;;
        -*)
            printf 'error: unknown option %s\n' "$1" >&2
            usage
            ;;
        *)
            if [[ -n "$role" ]]; then
                usage
            fi
            role="$1"
            cli_role=1
            ;;
    esac
    shift
done

if [[ -n "$role_flag" ]]; then
    if [[ -n "$role" && "$role" != "$role_flag" ]]; then
        usage
    fi
    role="$role_flag"
    cli_role=1
fi

require_user

if [[ "$list_subroles" -eq 1 ]]; then
    log "known subroles"
    known_subroles
    log "enabled subroles ($(subroles_file))"
    if [[ -z "$(read_saved_subroles)" ]]; then
        printf '(none)\n'
    else
        read_saved_subroles
    fi
    exit 0
fi

if [[ "$do_reset" -eq 1 && "$do_abort" -eq 1 ]]; then
    usage
fi

if [[ "$force" -eq 1 ]]; then
    die "--force does not strip packages; role.sh --reset is the walk-away flow"
fi

if [[ "$do_abort" -eq 1 ]]; then
    reset_abort
fi

if [[ "$do_reset" -eq 1 ]]; then
    run_reset
fi

if ! command -v git >/dev/null 2>&1; then
    log "bootstrap git (missing on this root)"
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        printf 'dry-run: sudo dnf install -y git\n'
    else
        sudo dnf install -y git
        command -v git >/dev/null 2>&1 || die "git is still missing after dnf install"
    fi
fi

ensure_hostname "${hostname_arg}"

if [[ -z "$role" ]]; then
    role="$(read_saved_role || true)"
fi
[[ -n "$role" ]] || die "no role saved; pass workstation, htpc, or server once"
valid_role "$role" || die "unknown role ${role}"

for name in "${enable_subroles[@]}"; do
    enable_saved_subrole "$name"
done
for name in "${disable_subroles[@]}"; do
    if ! valid_subrole "$name" && ! has_subrole "$name"; then
        die "unknown subrole ${name}"
    fi
    disable_saved_subrole "$name"
done

record_role "$role"
load_subroles_env

run_full=1
if [[ "$cli_role" -eq 0 && ("${#enable_subroles[@]}" -gt 0 || "${#disable_subroles[@]}" -gt 0) ]]; then
    run_full=0
fi

if [[ "$run_full" -eq 1 ]]; then
    while IFS= read -r module; do
        [[ -n "$module" ]] || continue
        run_module "$module"
    done < <(role_modules "$role")
else
    for name in "${enable_subroles[@]}"; do
        while IFS= read -r module; do
            [[ -n "$module" ]] || continue
            run_module "$module"
        done < <(subrole_modules "$name")
    done
    if [[ "${#disable_subroles[@]}" -gt 0 && "${#enable_subroles[@]}" -eq 0 ]]; then
        log "disabled subroles: ${disable_subroles[*]}"
        log "packages already installed are left in place; next update-role skips those modules"
    fi
fi

restart_qs_if_needed
