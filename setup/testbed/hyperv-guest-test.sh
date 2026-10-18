#!/usr/bin/env bash
# hyperv-guest is a no-op unless systemd-detect-virt prints microsoft,
# and the server role pulls that subrole in.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
module="${repo}/setup/modules/host/configure-hyperv-guest.sh"
conf="${repo}/setup/files/hyperv/hyperv-guest.conf"
hosts="${repo}/setup/files/boinc/hosts.list"
roles="${repo}/setup/roles.conf"

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

[[ -x "$module" ]] || fail "module is not executable"
[[ -f "$conf" ]] || fail "missing dracut drop-in"

grep -q 'hv_vmbus' "$conf" || fail "dracut drop-in misses hv_vmbus"
grep -q 'hv_storvsc' "$conf" || fail "dracut drop-in misses hv_storvsc"
grep -q 'hv_netvsc' "$conf" || fail "dracut drop-in misses hv_netvsc"
grep -q 'hv_utils' "$conf" || fail "dracut drop-in misses hv_utils"
grep -q 'force_drivers' "$conf" || fail "dracut drop-in does not force the modules"

grep -qx 'brood-drake' "$hosts" || fail "hosts.list is missing brood-drake"
grep -qx 'hoard-drake' "$hosts" || fail "hosts.list lost hoard-drake"
grep -qx 'roost-drake' "$hosts" || fail "hosts.list lost roost-drake"
awk '
    /^# servers$/ { in_servers=1; next }
    /^#/ { in_servers=0 }
    in_servers && $0 == "brood-drake" { found=1 }
    END { exit !found }
' "$hosts" || fail "brood-drake is not under # servers"

grep -q '@subrole.hyperv-guest' "$roles" || fail "server role does not pull in the subrole"
awk '
    /^\[server\]/ { in_server=1; next }
    /^\[/ { in_server=0 }
    in_server && $0 == "@subrole.hyperv-guest" { found=1 }
    END { exit !found }
' "$roles" || fail "@subrole.hyperv-guest is not in [server]"
awk '
    /^\[subrole.hyperv-guest\]/ { in_sub=1; next }
    /^\[/ { in_sub=0 }
    in_sub && $0 == "configure-hyperv-guest" { found=1 }
    END { exit !found }
' "$roles" || fail "subrole does not run configure-hyperv-guest"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
tree="${work}/tree"
mkdir -p "${tree}/setup/modules/host" "${tree}/setup/files/hyperv" \
    "${tree}/setup/lib" "${work}/home/.config/dot-files" "${work}/bin" "${work}/novirt"
ln -s /usr/bin/dirname /usr/bin/id "${work}/novirt/"
cp "$module" "${tree}/setup/modules/host/configure-hyperv-guest.sh"
cp "$conf" "${tree}/setup/files/hyperv/hyperv-guest.conf"
cp "$roles" "${tree}/setup/roles.conf"
chmod 0755 "${tree}/setup/modules/host/configure-hyperv-guest.sh"

# Stand-in for machine-setup setup/lib. The section walker matches
# setup/lib/roles.sh, and role_modules matches setup/subroles.sh with no
# saved subroles. Dry-run lines match ensure_packages and run.
cat >"${tree}/setup/lib/lib.sh" <<'EOF'
# shellcheck shell=bash
if [[ -n "${DOTFILES_LIB_LOADED:-}" ]]; then
    return 0
fi
DOTFILES_LIB_LOADED=1

log() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
run() {
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        printf 'dry-run: %s\n' "$*"
        return 0
    fi
    "$@"
}
require_user() {
    if [[ "$(id -un)" != "${DOTFILES_USER}" ]]; then
        die "run this as ${DOTFILES_USER}, not $(id -un)"
    fi
}
ensure_packages() {
    [[ "$#" -eq 0 ]] && return 0
    log "install packages: $*"
    run sudo dnf install -y "$@"
}
enable_service() {
    local unit="$1"
    if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
        return 0
    fi
    log "enable ${unit}"
    run sudo systemctl enable "$unit"
}
_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="$(cd "${_lib_dir}/.." && pwd)"
SETUP_FILES_DIR="${SETUP_DIR}/files"
CONFIG_TARGET_DIR="${DOTFILES_HOME}/.config"

subroles_file() {
    printf '%s\n' "${CONFIG_TARGET_DIR}/dot-files/subroles"
}
read_saved_subroles() {
    local file name
    file="$(subroles_file)"
    [[ -f "$file" ]] || return 0
    while IFS= read -r name || [[ -n "$name" ]]; do
        name="${name%%#*}"
        name="${name#"${name%%[![:space:]]*}"}"
        name="${name%"${name##*[![:space:]]}"}"
        [[ -n "$name" ]] && printf '%s\n' "$name"
    done <"$file"
}
valid_role() {
    case "${1:-}" in
        workstation | htpc | server | haos) return 0 ;;
        *) return 1 ;;
    esac
}
_role_section() {
    local conf="$1"
    local section="$2"
    local line current=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" ]] && continue
        if [[ "$line" == \[*\] ]]; then
            current="${line#[}"
            current="${current%]}"
            continue
        fi
        [[ "$current" == "$section" ]] || continue
        if [[ "$line" == @* ]]; then
            _role_section "$conf" "${line#@}"
        else
            printf '%s\n' "$line"
        fi
    done <"$conf"
}
role_modules() {
    local role="$1"
    local conf="${SETUP_DIR}/roles.conf"
    local sub
    valid_role "$role" || die "unknown role ${role}"
    [[ -f "$conf" ]] || die "missing ${conf}"
    if [[ "$role" == haos ]]; then
        _role_section "$conf" haos
        return 0
    fi
    _role_section "$conf" common
    _role_section "$conf" "$role"
    while IFS= read -r sub; do
        [[ -n "$sub" ]] || continue
        _role_section "$conf" "subrole.${sub}"
    done < <(read_saved_subroles)
}
EOF

export DOTFILES_HOME="${work}/home"
export DOTFILES_USER="$(id -un)"
unset DOTFILES_LIB_LOADED
# shellcheck disable=SC1091
. "${tree}/setup/lib/lib.sh"
server_list="$(role_modules server)"
grep -qx 'configure-hyperv-guest' <<<"$server_list" \
    || fail "server module list lost configure-hyperv-guest"
grep -qx 'install-boinc' <<<"$server_list" \
    || fail "server module list lost install-boinc"

cat >"${work}/bin/dnf" <<'EOF'
#!/bin/sh
printf 'dnf should not run: %s\n' "$*" >&2
exit 99
EOF
cat >"${work}/bin/systemd-detect-virt" <<'EOF'
#!/bin/sh
printf '%s\n' "${VIRT_NAME:-none}"
EOF
chmod 0755 "${work}/bin/dnf" "${work}/bin/systemd-detect-virt"

copied="${tree}/setup/modules/host/configure-hyperv-guest.sh"
run_user="$(id -un)"
run_module() {
    PATH="${1}" DOTFILES_HOME="${work}/home" DOTFILES_USER="$run_user" \
        /usr/bin/bash "$copied" 2>&1
}

skip_out="$(VIRT_NAME=kvm run_module "${work}/bin:${PATH}")"
grep -q 'not a Hyper-V guest (kvm); skipping' <<<"$skip_out" \
    || fail "kvm run did not skip: ${skip_out}"
grep -q 'install packages' <<<"$skip_out" && fail "kvm run tried to install packages"

unset VIRT_NAME
skip_out="$(run_module "${work}/bin:${PATH}")"
grep -q 'not a Hyper-V guest (none); skipping' <<<"$skip_out" \
    || fail "none run did not skip: ${skip_out}"

skip_out="$(run_module "${work}/novirt")"
grep -q 'not a Hyper-V guest (unknown); skipping' <<<"$skip_out" \
    || fail "missing detector did not skip: ${skip_out}"

dracut_dest="${work}/hyperv-guest.conf"
dry_out="$(VIRT_NAME=microsoft DOTFILES_DRY_RUN=1 HYPERV_DRACUT_CONF="$dracut_dest" \
    run_module "${work}/bin:${PATH}")"
grep -q 'install packages: hyperv-tools chrony' <<<"$dry_out" \
    || fail "dry-run did not install the packages: ${dry_out}"
grep -q 'dry-run: drop-in hypervkvpd.service -> /usr/bin/hv_kvp_daemon' <<<"$dry_out" \
    || fail "dry-run missed the KVP drop-in: ${dry_out}"
grep -q 'dry-run: start hypervvssd.service' <<<"$dry_out" \
    || fail "dry-run missed VSS: ${dry_out}"
grep -q 'dry-run: start hypervfcopyd.service' <<<"$dry_out" \
    || fail "dry-run missed file copy: ${dry_out}"
grep -q 'dry-run: start chronyd.service' <<<"$dry_out" \
    || fail "dry-run missed chronyd: ${dry_out}"
grep -q 'dry-run: dracut -f' <<<"$dry_out" \
    || fail "dry-run missed the initramfs rebuild: ${dry_out}"
grep -q 'dnf should not run' <<<"$dry_out" && fail "dry-run executed dnf"

cp "$conf" "$dracut_dest"
same_out="$(VIRT_NAME=microsoft DOTFILES_DRY_RUN=1 HYPERV_DRACUT_CONF="$dracut_dest" \
    run_module "${work}/bin:${PATH}")"
grep -q 'dry-run: dracut -f' <<<"$same_out" \
    && fail "unchanged dracut drop-in rebuilt initramfs: ${same_out}"
grep -q 'write ' <<<"$same_out" \
    && fail "unchanged dracut drop-in was rewritten: ${same_out}"

printf 'force_drivers+=" hv_vmbus "\n' >"$dracut_dest"
changed_out="$(VIRT_NAME=microsoft DOTFILES_DRY_RUN=1 HYPERV_DRACUT_CONF="$dracut_dest" \
    run_module "${work}/bin:${PATH}")"
grep -q 'dry-run: dracut -f' <<<"$changed_out" \
    || fail "changed dracut drop-in did not rebuild: ${changed_out}"

bad_out="$(VIRT_NAME=microsoft DOTFILES_DRY_RUN=1 HYPERV_DRACUT_CONF=/etc/dracut.conf.d/hyperv-guest.conf \
    run_module "${work}/bin:${PATH}" || true)"
grep -q 'HYPERV_DRACUT_CONF must sit under /tmp' <<<"$bad_out" \
    || fail "override outside /tmp was accepted: ${bad_out}"

printf '%s\n' "hyperv-guest ok"
