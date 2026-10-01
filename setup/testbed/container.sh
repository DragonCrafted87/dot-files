#!/usr/bin/env bash
# Everyday OpenMandriva bench for role and module runs.
# systemd is not PID 1. systemctl failures stay failures.
set -euo pipefail

IMAGE="openmandriva/minimal:rock"
NAME="dotfiles-testbed"
VOLUME="dotfiles-testbed-home"
GUEST_USER="dragon"
GUEST_HOME="/home/${GUEST_USER}"
GUEST_REPO="${GUEST_HOME}/dot-files"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${here}/../.." && pwd)"

use_secrets=0
with_source=0
copied_paths=()

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

warn() {
    printf 'warning: %s\n' "$*" >&2
}

need_docker() {
    command -v docker >/dev/null 2>&1 || die "docker is required"
}

image_ready() {
    docker image inspect "$IMAGE" >/dev/null 2>&1 || docker pull "$IMAGE"
}

container_exists() {
    docker container inspect "$NAME" >/dev/null 2>&1
}

init_guest() {
    local uid gid
    uid="$(id -u)"
    gid="$(id -g)"
    docker exec -i -u root -e HOST_UID="$uid" -e HOST_GID="$gid" "$NAME" \
        bash -s <<'EOS'
set -euo pipefail
if ! command -v sudo >/dev/null 2>&1; then
    dnf install -y sudo
fi
# The image installs sudo without the setuid bit, so sudo -n fails.
chmod 4755 /usr/bin/sudo
if [[ -e /usr/sbin/sudo && ! -L /usr/sbin/sudo ]]; then
    chmod 4755 /usr/sbin/sudo
fi
if ! command -v useradd >/dev/null 2>&1; then
    dnf install -y shadow-utils
fi
if ! command -v hostname >/dev/null 2>&1; then
    dnf install -y hostname
fi
if ! getent group "$HOST_GID" >/dev/null 2>&1; then
    groupadd --gid "$HOST_GID" dragon
fi
if ! id dragon >/dev/null 2>&1; then
    # The rock image ships user omv at uid 1001. The host uid must be
    # dragon so the bind-mounted repo stays writable.
    if getent passwd "$HOST_UID" >/dev/null 2>&1; then
        userdel "$(getent passwd "$HOST_UID" | cut -d: -f1)"
    fi
    useradd --uid "$HOST_UID" --gid "$HOST_GID" --no-create-home \
        --home-dir /home/dragon --shell /bin/bash dragon
fi
install -d -o dragon -g "$HOST_GID" /home/dragon
cat >/etc/sudoers.d/dragon <<'SUDO'
Defaults:dragon !requiretty
dragon ALL=(ALL) NOPASSWD: ALL
SUDO
chmod 0440 /etc/sudoers.d/dragon
EOS
}

create_container() {
    docker volume inspect "$VOLUME" >/dev/null 2>&1 \
        || docker volume create "$VOLUME" >/dev/null
    docker create \
        --name "$NAME" \
        --hostname testbed \
        --mount "type=volume,source=${VOLUME},target=${GUEST_HOME}" \
        --mount "type=bind,source=${REPO},target=${GUEST_REPO}" \
        "$IMAGE" \
        sleep infinity >/dev/null
}

cmd_start() {
    need_docker
    image_ready
    if ! container_exists; then
        create_container
    fi
    docker start "$NAME" >/dev/null
    init_guest
}

stop_container() {
    if container_exists; then
        docker stop "$NAME" >/dev/null || true
        docker rm "$NAME" >/dev/null
    fi
}

cmd_rebuild() {
    need_docker
    stop_container
    cmd_start
}

cmd_wipe_home() {
    need_docker
    stop_container
    if docker volume inspect "$VOLUME" >/dev/null 2>&1; then
        docker volume rm "$VOLUME" >/dev/null
    fi
    cmd_start
}

guest_exec() {
    docker exec -u "$GUEST_USER" \
        -e "REPO_ROOT=${GUEST_REPO}" \
        -e "DOTFILES_ROOT=${GUEST_REPO}" \
        "$NAME" \
        "$@"
}

copy_secrets() {
    local list rel src parent
    list="${DOTFILES_TESTBED_SECRETS_LIST:-${REPO}/setup/files/secrets.list}"
    [[ -f "$list" ]] || die "missing secrets list ${list}"
    copied_paths=()
    while IFS= read -r rel || [[ -n "$rel" ]]; do
        [[ -z "$rel" || "$rel" == \#* ]] && continue
        src="${HOME}/${rel}"
        if [[ ! -e "$src" ]]; then
            warn "missing secret ${src}"
            continue
        fi
        parent="$(dirname "$rel")"
        if [[ "$parent" != "." ]]; then
            docker exec -u root "$NAME" mkdir -p -- "${GUEST_HOME}/${parent}"
        fi
        docker cp "$src" "${NAME}:${GUEST_HOME}/${rel}"
        docker exec -u root "$NAME" chown dragon:dragon -- "${GUEST_HOME}/${rel}"
        copied_paths+=("$rel")
    done <"$list"
}

cleanup_secrets() {
    local rel
    [[ ${#copied_paths[@]} -eq 0 ]] && return 0
    for rel in "${copied_paths[@]}"; do
        docker exec -u root "$NAME" rm -f -- "${GUEST_HOME}/${rel}" || true
    done
    copied_paths=()
}

run_guarded() {
    local rc=0
    if [[ "$use_secrets" -eq 1 ]]; then
        copy_secrets
        trap cleanup_secrets EXIT
    fi
    "$@" || rc=$?
    if [[ "$use_secrets" -eq 1 ]]; then
        cleanup_secrets
        trap - EXIT
    fi
    return "$rc"
}

cmd_exec() {
    [[ "$#" -gt 0 ]] || die "exec needs a command"
    cmd_start
    run_guarded guest_exec "$@"
}

cmd_shell() {
    cmd_start
    if [[ -t 0 && -t 1 ]]; then
        run_guarded docker exec -it -u "$GUEST_USER" \
            -e "REPO_ROOT=${GUEST_REPO}" \
            -e "DOTFILES_ROOT=${GUEST_REPO}" \
            "$NAME" bash
    else
        run_guarded guest_exec bash
    fi
}

skip_list() {
    if [[ "$with_source" -eq 1 ]]; then
        printf ''
    else
        printf 'install-hyprland-source'
    fi
}

cmd_role() {
    local role="${1:-workstation}"
    cmd_start
    run_guarded docker exec -u "$GUEST_USER" \
        -e "REPO_ROOT=${GUEST_REPO}" \
        -e "DOTFILES_ROOT=${GUEST_REPO}" \
        -e "DOTFILES_SKIP_MODULES=$(skip_list)" \
        "$NAME" \
        bash "${GUEST_REPO}/setup/role.sh" "$role"
}

cmd_module() {
    local name="${1:-}"
    local host_path rel
    [[ -n "$name" ]] || die "module needs a name"
    host_path="$(
        # shellcheck disable=SC1091
        SETUP_DIR="${REPO}/setup" . "${REPO}/setup/lib/lib.sh"
        find_module "$name"
    )" || die "missing module: ${name}"
    rel="${host_path#"${REPO}/"}"
    cmd_start
    run_guarded guest_exec bash "${GUEST_REPO}/${rel}"
}

role_dry_run() {
    local skip="$1"
    docker exec -u "$GUEST_USER" \
        -e "REPO_ROOT=${GUEST_REPO}" \
        -e "DOTFILES_ROOT=${GUEST_REPO}" \
        -e "DOTFILES_SKIP_MODULES=${skip}" \
        "$NAME" \
        bash "${GUEST_REPO}/setup/role.sh" --dry-run workstation
}

cmd_smoke() {
    local uid out
    cmd_start
    uid="$(id -u)"
    docker exec -i -u "$GUEST_USER" -e HOST_UID="$uid" "$NAME" bash -s <<'EOS'
set -euo pipefail
[[ "$(id -u)" == "$HOST_UID" ]]
sudo -n true
[[ -f /home/dragon/dot-files/setup/role.sh ]]
EOS
    set +e
    out="$(role_dry_run install-hyprland-source)"
    local rc=$?
    set -e
    printf '%s\n' "$out"
    [[ "$rc" -eq 0 ]] || die "dry-run role failed with the hyprland skip"
    grep -F 'skip module install-hyprland-source' <<<"$out" >/dev/null
    set +e
    out="$(role_dry_run "")"
    rc=$?
    set -e
    printf '%s\n' "$out"
    [[ "$rc" -eq 0 ]] || die "dry-run role failed with an empty skip list"
    if grep -F 'skip module install-hyprland-source' <<<"$out" >/dev/null; then
        die "hyprland source was skipped when the skip list is empty"
    fi
    grep -F 'module install-hyprland-source' <<<"$out" >/dev/null
}

usage() {
    cat <<EOF
usage: $(basename "$0") [--secrets] [--with-hyprland-source] <command>

  start
  shell
  role [name]          default workstation
  module <name>
  exec <command...>
  smoke
  wipe-home
  rebuild
EOF
    exit 2
}

main() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --secrets)
                use_secrets=1
                shift
                ;;
            --with-hyprland-source)
                with_source=1
                shift
                ;;
            -h | --help)
                usage
                ;;
            *)
                break
                ;;
        esac
    done
    local cmd="${1:-}"
    [[ -n "$cmd" ]] || usage
    shift
    case "$cmd" in
        start) cmd_start ;;
        shell) cmd_shell "$@" ;;
        role) cmd_role "$@" ;;
        module) cmd_module "$@" ;;
        exec) cmd_exec "$@" ;;
        smoke) cmd_smoke "$@" ;;
        wipe-home) cmd_wipe_home "$@" ;;
        rebuild) cmd_rebuild "$@" ;;
        *) die "unknown command ${cmd}" ;;
    esac
}

main "$@"
