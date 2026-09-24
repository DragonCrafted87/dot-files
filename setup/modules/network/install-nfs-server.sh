#!/usr/bin/env bash
# NFS server subrole. Installs nfs-utils, enables nfs-server, and drops
# a commented exports snippet. Share paths stay local to the box.
#
#   ~/dot-files/setup/role.sh --enable-subrole nfs-server

set -euo pipefail
# shellcheck disable=SC1091
. "${REPO_ROOT:-$DOTFILES_ROOT}/setup/lib/lib.sh"

require_user

pkg=""
pkg="$(pick_pkg nfs-utils nfs-kernel-server nfs-server || true)"
if [[ -z "$pkg" ]]; then
    die "no nfs server package found (tried nfs-utils nfs-kernel-server nfs-server)"
fi
ensure_packages "$pkg"

if pick_pkg rpcbind >/dev/null 2>&1; then
    ensure_packages rpcbind
    enable_service rpcbind.service
fi

unit=""
for candidate in nfs-server.service nfs-kernel-server.service nfs.service; do
    if systemctl list-unit-files "$candidate" >/dev/null 2>&1; then
        unit="$candidate"
        break
    fi
done
[[ -n "$unit" ]] || die "nfs server unit not found after installing ${pkg}"
enable_service "$unit"
if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
    run sudo systemctl start "$unit" || warn "could not start ${unit}"
fi

exports_dir="/etc/exports.d"
exports_file="${exports_dir}/dot-files.exports"
exports_body="# Managed by dot-files subrole nfs-server.
# Uncomment and edit a line, then run: sudo exportfs -ra
#
# /srv/share  192.168.0.0/16(rw,sync,no_subtree_check,no_root_squash)
"
if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
    log "dry-run: write ${exports_file}"
else
    if [[ ! -f "$exports_file" ]]; then
        log "write ${exports_file}"
        run sudo mkdir -p "$exports_dir"
        printf '%s\n' "$exports_body" | run sudo tee "$exports_file" >/dev/null
        run sudo chmod 0644 "$exports_file"
    else
        log "keep existing ${exports_file}"
    fi
    run sudo exportfs -ra || warn "exportfs -ra failed; edit ${exports_file}"
fi
