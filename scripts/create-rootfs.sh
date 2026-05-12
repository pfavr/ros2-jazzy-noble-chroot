#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

need_root "$@"

if rootfs_exists; then
  echo "Rootfs already exists at ${ROOTFS_DIR}"
  exit 0
fi

if [[ ! -x "${DEBOOTSTRAP}" ]]; then
  echo "debootstrap not found at ${DEBOOTSTRAP}. Install it on the host first." >&2
  exit 1
fi

mkdir -p "${ROOTFS_DIR}"
"${DEBOOTSTRAP}" --arch=amd64 "${UBUNTU_CODENAME}" "${ROOTFS_DIR}" "${UBUNTU_MIRROR}"

cat > "${ROOTFS_DIR}/etc/apt/sources.list" <<APT_SOURCES
deb ${UBUNTU_MIRROR} ${UBUNTU_CODENAME} main universe restricted multiverse
deb ${UBUNTU_MIRROR} ${UBUNTU_CODENAME}-updates main universe restricted multiverse
deb ${UBUNTU_MIRROR} ${UBUNTU_CODENAME}-security main universe restricted multiverse
APT_SOURCES

cp --remove-destination /etc/resolv.conf "${ROOTFS_DIR}/etc/resolv.conf"
echo "Created Ubuntu ${UBUNTU_CODENAME} rootfs at ${ROOTFS_DIR}"
