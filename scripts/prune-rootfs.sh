#!/usr/bin/env bash
# Reclaim disk space from a built rootfs in-place. Mirrors the exclusions
# that scripts/pack-rootfs.sh applies when creating the redistributable
# tarball, so running this against a release build leaves a functional
# (runnable) rootfs that just can no longer be incrementally rebuilt.
#
# Removed:
#   opt/ros2_ws/build/             (~9 GB) colcon build trees
#   opt/ros2_ws/log/               (~100 MB) colcon logs
#   var/cache/apt/archives/*.deb   (~650 MB) downloaded packages
#   var/lib/apt/lists/*            (~250 MB) apt indices (rebuilt by apt-get update)
#   root/.cache, home/ros2/.cache  pip / misc caches
#   tmp/*                          stray temp files
#
# Kept (deliberately):
#   opt/ros2_ws/src/      so users can rebuild ROS or add overlay packages
#                         that need full sources (msg/srv generators, headers).
#   opt/ros2_ws/install/  the actual ROS install.
#
# Refuses to run unless the rootfs was built with BUILD_MODE=release; with
# --symlink-install the install/ tree depends on build/ and src/ and would
# be broken by this prune.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

usage() {
  cat <<USAGE
Usage: sudo $0 [--dry-run] [--force]

  --dry-run   Show what would be removed, but do not delete anything.
  --force     Skip the BUILD_MODE=release safety check (use only if you know
              install/ does not contain symlinks back into build/ or src/).
USAGE
}

dry_run=0
force=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) dry_run=1; shift ;;
    --force)   force=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

need_root "$@"
require_rootfs
"${REPO_ROOT}/scripts/umount-rootfs.sh" || true

marker="${ROOTFS_DIR}${ROS_WORKSPACE}/.build_mode"
if [[ ${force} -eq 0 ]]; then
  if [[ ! -f "${marker}" ]]; then
    die "Cannot determine BUILD_MODE (no ${marker}). Rerun scripts/build-ros2.sh, or pass --force if you are sure install/ has no symlinks into build/."
  fi
  mode=$(cat "${marker}")
  if [[ "${mode}" != "release" ]]; then
    die "Rootfs was built with BUILD_MODE=${mode}; pruning build/ would break install/. Rebuild with BUILD_MODE=release, or rerun with --force at your own risk."
  fi
fi

targets=(
  "${ROOTFS_DIR}${ROS_WORKSPACE}/build"
  "${ROOTFS_DIR}${ROS_WORKSPACE}/log"
  "${ROOTFS_DIR}/root/.cache"
  "${ROOTFS_DIR}/home/${ROS_USER}/.cache"
)

glob_targets=(
  "${ROOTFS_DIR}/var/cache/apt/archives/"*.deb
  "${ROOTFS_DIR}/var/cache/apt/archives/partial/"*
  "${ROOTFS_DIR}/var/lib/apt/lists/"*
  "${ROOTFS_DIR}/tmp/"*
)

report_size() {
  local path=$1
  if [[ -e "${path}" ]]; then
    du -sh "${path}" 2>/dev/null | awk '{print $1"\t"$2}'
  fi
}

echo "Before:"
du -sh "${ROOTFS_DIR}" 2>/dev/null || true
echo

echo "Will remove:"
for t in "${targets[@]}"; do report_size "${t}"; done
for t in "${glob_targets[@]}"; do
  [[ -e "${t}" ]] && report_size "${t}"
done

if [[ ${dry_run} -eq 1 ]]; then
  echo
  echo "Dry run: nothing deleted."
  exit 0
fi

echo
echo "Pruning..."
for t in "${targets[@]}"; do
  [[ -e "${t}" ]] && rm -rf -- "${t}"
done
for t in "${glob_targets[@]}"; do
  [[ -e "${t}" ]] && rm -rf -- "${t}"
done

# Recreate empty cache dirs apt expects.
install -d -m 0755 "${ROOTFS_DIR}/var/cache/apt/archives/partial"
install -d -m 0755 "${ROOTFS_DIR}/var/lib/apt/lists/partial"

echo
echo "After:"
du -sh "${ROOTFS_DIR}" 2>/dev/null || true
echo
echo "To rebuild ROS 2 inside the rootfs:"
echo "  sudo ./scripts/ros2-chroot.sh"
echo "  cd ${ROS_WORKSPACE} && . venv/bin/activate && colcon build --base-paths src"
echo "(apt-get update inside the chroot is needed before any apt install.)"
