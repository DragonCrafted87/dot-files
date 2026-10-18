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
mkdir -p "${work}/home/.config/dot-files" "${work}/home/dot-files" "${work}/bin"
printf 'dot-files=%s\nmachine-setup=%s\n' "${work}/home/dot-files" "$repo" \
    >"${work}/home/.config/dot-files/checkouts"
export DOTFILES_HOME="${work}/home"
export DOTFILES_USER="$(id -un)"
unset DOTFILES_LIB_LOADED
# shellcheck disable=SC1091
. "${repo}/setup/lib/lib.sh"
server_list="$(role_modules server)"
grep -qx 'configure-hyperv-guest' <<<"$server_list" || fail "server module list lost configure-hyperv-guest"
grep -qx 'install-boinc' <<<"$server_list" || fail "server module list lost install-boinc"

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

run_module() {
    PATH="${work}/bin:${PATH}" DOTFILES_HOME="${work}/home" DOTFILES_USER="$(id -un)" \
        bash "$module"
}

skip_out="$(VIRT_NAME=kvm run_module)"
grep -q 'not a Hyper-V guest (kvm); skipping' <<<"$skip_out" || fail "kvm run did not skip: ${skip_out}"
grep -q 'install packages' <<<"$skip_out" && fail "kvm run tried to install packages"

unset VIRT_NAME
skip_out="$(run_module)"
grep -q 'not a Hyper-V guest (none); skipping' <<<"$skip_out" || fail "none run did not skip: ${skip_out}"

dry_out="$(VIRT_NAME=microsoft DOTFILES_DRY_RUN=1 run_module)"
grep -q 'install packages: hyperv-tools chrony' <<<"$dry_out" || fail "dry-run did not install the packages: ${dry_out}"
grep -q 'dry-run: drop-in hypervkvpd.service -> /usr/bin/hv_kvp_daemon' <<<"$dry_out" \
    || fail "dry-run missed the KVP drop-in: ${dry_out}"
grep -q 'dry-run: start hypervvssd.service' <<<"$dry_out" || fail "dry-run missed VSS: ${dry_out}"
grep -q 'dry-run: start hypervfcopyd.service' <<<"$dry_out" || fail "dry-run missed file copy: ${dry_out}"
grep -q 'dry-run: start chronyd.service' <<<"$dry_out" || fail "dry-run missed chronyd: ${dry_out}"
grep -q 'dry-run: dracut -f' <<<"$dry_out" || fail "dry-run missed the initramfs rebuild: ${dry_out}"
grep -q 'dnf should not run' <<<"$dry_out" && fail "dry-run executed dnf"

printf '%s\n' "hyperv-guest ok"
