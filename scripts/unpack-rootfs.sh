#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/ros2-${ROS_DISTRO}-${UBUNTU_CODENAME}-rootfs.tar.zst" >&2
  exit 2
fi

archive=$1

need_root "$@"

if [[ ! -f "${archive}" ]]; then
  echo "Archive not found: ${archive}" >&2
  exit 1
fi

if rootfs_exists; then
  echo "Rootfs already exists at ${ROOTFS_DIR}. Move it aside before unpacking." >&2
  exit 1
fi

if ! command -v zstd >/dev/null 2>&1; then
  echo "zstd is required on the host to unpack compressed rootfs archives." >&2
  exit 1
fi

mkdir -p "${ROOTFS_DIR}"
# Artifacts produced by pack-rootfs.sh have the layout
#   <stem>/rootfs/...        (the chroot contents)
#   <stem>/ros2-chroot.sh    (top-level symlink, for standalone use)
#   <stem>/README.md
#   <stem>/ARTIFACT_INFO
# For the in-tree dev flow we only want the rootfs payload, dropped at
# ${ROOTFS_DIR}. --strip-components=2 removes the "<stem>/rootfs/" prefix,
# and the wildcard filters out the top-level helper files.
tar --xattrs --acls --numeric-owner -I zstd -xpf "${archive}" \
    -C "${ROOTFS_DIR}" \
    --strip-components=2 \
    --wildcards '*/rootfs/*'
cp --remove-destination /etc/resolv.conf "${ROOTFS_DIR}/etc/resolv.conf"

echo "Unpacked ${archive} into ${ROOTFS_DIR}"