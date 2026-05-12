#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

need_root "$@"

require_rootfs

mkdir -p "${ROOTFS_DIR}/dev" "${ROOTFS_DIR}/dev/pts" "${ROOTFS_DIR}/proc" "${ROOTFS_DIR}/sys" "${ROOTFS_DIR}/run"

mountpoint -q "${ROOTFS_DIR}/dev" || mount --bind /dev "${ROOTFS_DIR}/dev"
mountpoint -q "${ROOTFS_DIR}/dev/pts" || mount --bind /dev/pts "${ROOTFS_DIR}/dev/pts"
mountpoint -q "${ROOTFS_DIR}/proc" || mount -t proc proc "${ROOTFS_DIR}/proc"
mountpoint -q "${ROOTFS_DIR}/sys" || mount -t sysfs sysfs "${ROOTFS_DIR}/sys"
mountpoint -q "${ROOTFS_DIR}/run" || mount --bind /run "${ROOTFS_DIR}/run"
cp --remove-destination /etc/resolv.conf "${ROOTFS_DIR}/etc/resolv.conf"

echo "Mounted chroot support filesystems."
