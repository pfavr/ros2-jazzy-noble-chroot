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
rm -f "${REPO_ROOT}/build-host.log" "${REPO_ROOT}/rosdep-check.log"

if [[ ${remove_artifacts} -eq 1 ]]; then
  rm -rf --one-file-system "${REPO_ROOT}/artifacts"
fi

echo "Removed generated rootfs and local build logs."
if [[ ${remove_artifacts} -eq 1 ]]; then
  echo "Removed artifacts directory."
fi
