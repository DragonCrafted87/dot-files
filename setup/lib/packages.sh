# shellcheck shell=bash
# Sourced by setup/lib/lib.sh. Not an entry point.

# OpenMandriva ships generic x86_64 ISOs even on Zen machines, so rpm
# %{_arch} is not enough. Use the CPU family: AMD family 23+ is Zen and
# takes the znver1 repos.
detect_omv_repo_arch() {
    local vendor family model
    vendor="$(awk -F: '/^vendor_id/{gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo)"
    family="$(awk -F: '/^cpu family/{gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo)"
    model="$(uname -m)"
    if [[ "$model" == "aarch64" ]]; then
        printf '%s\n' aarch64
        return 0
    fi
    if [[ "$vendor" == "AuthenticAMD" && "${family:-0}" -ge 23 ]]; then
        printf '%s\n' znver1
        return 0
    fi
    printf '%s\n' x86_64
}

ensure_packages() {
    if [[ "$#" -eq 0 ]]; then
        return 0
    fi
    log "install packages: $*"
    run sudo dnf install -y "$@"
}

# First exact name that is installed or available. OpenMandriva names are
# lowercase. On 64-bit, libfoo-devel is the 32-bit compat package and
# lib64foo-devel is the real one — try lib64* first even if the caller
# listed the short name first. dnf list can be sloppy about case and
# still exit 0; repoquery + rpm -q stay exact.
pick_pkg() {
    local p avail arch ordered=() rest=()
    arch="$(uname -m)"
    if [[ "$arch" == "x86_64" || "$arch" == "aarch64" ]]; then
        for p in "$@"; do
            if [[ "$p" == lib64* ]]; then
                ordered+=("$p")
            else
                rest+=("$p")
            fi
        done
        set -- "${ordered[@]}" "${rest[@]}"
    fi
    for p in "$@"; do
        if rpm -q "$p" >/dev/null 2>&1; then
            printf '%s\n' "$p"
            return 0
        fi
        avail="$(dnf -q repoquery --available --qf '%{name}\n' "$p" 2>/dev/null | head -n1 || true)"
        if [[ "$avail" == "$p" ]]; then
            printf '%s\n' "$p"
            return 0
        fi
    done
    return 1
}

# Rock 6.0 ships plasma6-* names for KF6 apps. The unprefixed names are
# leftover KF5 packages and file-conflict. Extra args install with the
# plasma6 package (okular extras, etc).
install_kf6_or_plain() {
    local plasma6_name="$1"
    local plain_name="$2"
    shift 2
    local extras=("$@")

    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        log "${plasma6_name} / ${plain_name} package"
        return 0
    fi
    if rpm -q "$plasma6_name" >/dev/null 2>&1; then
        log "${plasma6_name} already installed"
        return 0
    fi
    if rpm -q "$plain_name" >/dev/null 2>&1; then
        log "${plain_name} already installed"
        return 0
    fi
    if dnf list --available "$plasma6_name" >/dev/null 2>&1; then
        ensure_packages "$plasma6_name" "${extras[@]}"
    else
        ensure_packages "$plain_name"
    fi
}

ensure_flatpak_remote() {
    local name="$1"
    local url="$2"
    if flatpak remotes --columns=name 2>/dev/null | grep -qx "$name"; then
        return 0
    fi
    log "flatpak remote ${name}"
    run sudo flatpak remote-add --if-not-exists "$name" "$url"
}

ensure_flatpak() {
    local app="$1"
    if flatpak info "$app" >/dev/null 2>&1; then
        return 0
    fi
    log "flatpak install ${app}"
    run sudo flatpak install -y flathub "$app"
}

remove_packages() {
    local pkg
    local to_remove=()
    for pkg in "$@"; do
        if rpm -q "$pkg" >/dev/null 2>&1; then
            to_remove+=("$pkg")
        fi
    done
    if [[ "${#to_remove[@]}" -eq 0 ]]; then
        return 0
    fi
    log "remove packages: ${to_remove[*]}"
    run sudo dnf remove -y "${to_remove[@]}"
}
