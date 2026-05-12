#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

need_root "$@"

require_rootfs

mkdir -p "${ROOTFS_DIR}/dev" "${ROOTFS_DIR}/proc" "${ROOTFS_DIR}/sys" "${ROOTFS_DIR}/run"

# Use --rbind for /dev so the host's /dev/shm (and /dev/pts, /dev/mqueue, ...)
# submounts are visible inside the chroot. Plain --bind would leave /dev/shm
# as an empty 0755 directory, which breaks Fast-DDS SHM transport (and any
# other code that needs writable POSIX shared memory).
# --make-rslave then prevents an unmount inside the chroot from propagating
# back out to the host's /dev/shm.
if ! mountpoint -q "${ROOTFS_DIR}/dev"; then
  mount --rbind /dev "${ROOTFS_DIR}/dev"
  mount --make-rslave "${ROOTFS_DIR}/dev"
fi
mountpoint -q "${ROOTFS_DIR}/proc" || mount -t proc proc "${ROOTFS_DIR}/proc"
mountpoint -q "${ROOTFS_DIR}/sys" || mount -t sysfs sysfs "${ROOTFS_DIR}/sys"
if ! mountpoint -q "${ROOTFS_DIR}/run"; then
  mount --rbind /run "${ROOTFS_DIR}/run"
  mount --make-rslave "${ROOTFS_DIR}/run"
fi
cp --remove-destination /etc/resolv.conf "${ROOTFS_DIR}/etc/resolv.conf"

echo "Mounted chroot support filesystems."
