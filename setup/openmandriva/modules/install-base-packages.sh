#!/usr/bin/env bash
# CLI baseline for every role.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user
ensure_packages \
    git \
    curl \
    wget \
    unzip \
    7zip \
    unrar-free \
    gh \
    openssh-clients \
    openssh-server \
    tmux \
    htop \
    fastfetch \
    jq \
    nano \
    rsync \
    gnupg \
    python \
    python-pip \
    bind-utils \
    net-tools \
    traceroute \
    lm_sensors \
    smartmontools \
    fwupd \
    cifs-utils \
    nfs-utils \
    samba-client
