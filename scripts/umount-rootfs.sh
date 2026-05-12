#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

need_root "$@"

for target in run sys proc dev/pts dev; do
  mountpoint="${ROOTFS_DIR}/${target}"
  if mountpoint -q "${mountpoint}"; then
    umount "${mountpoint}"
  fi
done

echo "Unmounted chroot support filesystems."
