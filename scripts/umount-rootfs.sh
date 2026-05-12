#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

need_root "$@"

if [[ ! -d "${ROOTFS_DIR}" ]]; then
  echo "Rootfs directory does not exist at ${ROOTFS_DIR}."
  exit 0
fi

rootfs_path=$(cd -P -- "${ROOTFS_DIR}" && pwd)
mapfile -t mountpoints < <(
  findmnt -rn -o TARGET \
    | awk -v root="${rootfs_path}" '($0 == root) || (substr($0, 1, length(root) + 1) == root "/") { print length($0) "\t" $0 }' \
    | sort -rn \
    | cut -f2-
)

for mountpoint in "${mountpoints[@]}"; do
  if mountpoint -q "${mountpoint}"; then
    umount "${mountpoint}" || umount -l "${mountpoint}"
  fi
done

echo "Unmounted chroot support filesystems."
