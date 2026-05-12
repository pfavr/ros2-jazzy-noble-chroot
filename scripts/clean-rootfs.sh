#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

need_root "$@"

remove_artifacts=0
if [[ "${1:-}" == "--artifacts" ]]; then
  remove_artifacts=1
  shift
fi

if [[ $# -ne 0 ]]; then
  echo "Usage: $0 [--artifacts]" >&2
  exit 2
fi

"${REPO_ROOT}/scripts/umount-rootfs.sh"

rootfs_path=$(cd -P -- "$(dirname -- "${ROOTFS_DIR}")" && pwd)/$(basename -- "${ROOTFS_DIR}")
if findmnt -rn -o TARGET | awk -v root="${rootfs_path}" '($0 == root) || (substr($0, 1, length(root) + 1) == root "/") { found = 1 } END { exit found ? 0 : 1 }'; then
  echo "Refusing to remove ${ROOTFS_DIR}: mountpoints are still active underneath it." >&2
  findmnt -rn -o TARGET | awk -v root="${rootfs_path}" '($0 == root) || (substr($0, 1, length(root) + 1) == root "/") { print "  " $0 }' >&2
  exit 1
fi

rm -rf --one-file-system "${ROOTFS_DIR}"
# Remove only the per-step logs produced by build_all.sh, both the legacy in-tree
# location and the current logs/ directory. Avoid wiping unrelated *.log files.
step_logs=(check-host create-rootfs provision-rootfs fetch-sources build-ros2 build-host smoke-test pack-rootfs)
for name in "${step_logs[@]}"; do
  rm -f "${REPO_ROOT}/${name}.log" "${REPO_ROOT}/logs/${name}.log"
done
rmdir "${REPO_ROOT}/logs" 2>/dev/null || true

if [[ ${remove_artifacts} -eq 1 ]]; then
  rm -rf --one-file-system "${REPO_ROOT}/artifacts"
fi

echo "Removed generated rootfs and local build logs."
if [[ ${remove_artifacts} -eq 1 ]]; then
  echo "Removed artifacts directory."
fi
