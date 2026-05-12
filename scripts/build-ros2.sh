#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

need_root "$@"
require_rootfs
require_chroot_executable "${ROS_WORKSPACE}/venv/bin/colcon" "Run scripts/provision-rootfs.sh first."
require_chroot_path "${ROS_WORKSPACE}/src" "Run scripts/fetch-sources.sh first."
"${REPO_ROOT}/scripts/mount-rootfs.sh"
"${REPO_ROOT}/scripts/install-rosdeps.sh"

WORKERS=${WORKERS:-4}
BUILD_JOBS=${BUILD_JOBS:-8}
[[ "${WORKERS}" =~ ^[1-9][0-9]*$ ]] || die "WORKERS must be a positive integer."
[[ "${BUILD_JOBS}" =~ ^[1-9][0-9]*$ ]] || die "BUILD_JOBS must be a positive integer."

# BUILD_MODE controls the colcon install layout:
#   release (default) -> isolated install with file COPIES (no extra colcon
#       flags). install/ is self-contained: opt/ros2_ws/build can be deleted
#       afterwards without breaking the install. This is the layout used for
#       the redistributable tarball, where build-tree pruning saves ~9 GB.
#   dev               -> --symlink-install. install/ contains symlinks back
#       into build/ and src/, so editing Python sources or launch files takes
#       effect without rebuilding. Faster iteration, but build/ is NOT
#       removable.
# In both modes the layout is *isolated* (one install/<pkg>/ subdir per
# package): this is the colcon default and matches what ROS 2 tutorials and
# downstream users expect when looking for a package's launch files / msgs.
BUILD_MODE=${BUILD_MODE:-release}
case "${BUILD_MODE}" in
  release) colcon_layout_args=() ;;
  dev)     colcon_layout_args=(--symlink-install) ;;
  *) die "BUILD_MODE must be 'release' or 'dev' (got: ${BUILD_MODE})." ;;
esac

# If a previous build used a different mode, wipe build/ and install/ so the
# new mode starts clean (mixing symlink and copy installs leaves stale files).
layout_marker="${ROOTFS_DIR}${ROS_WORKSPACE}/.build_mode"
prev_mode=""
[[ -f "${layout_marker}" ]] && prev_mode=$(cat "${layout_marker}")
if [[ -n "${prev_mode}" && "${prev_mode}" != "${BUILD_MODE}" ]]; then
  echo "BUILD_MODE changed (${prev_mode} -> ${BUILD_MODE}); wiping build/ and install/."
  rm -rf -- "${ROOTFS_DIR}${ROS_WORKSPACE}/build" \
            "${ROOTFS_DIR}${ROS_WORKSPACE}/install" \
            "${ROOTFS_DIR}${ROS_WORKSPACE}/log"
fi

workspace=$(shell_quote "${ROS_WORKSPACE}")
run_as_ros_user "cd ${workspace} && . ${workspace}/venv/bin/activate && export CMAKE_BUILD_PARALLEL_LEVEL=${BUILD_JOBS} MAKEFLAGS=-j${BUILD_JOBS} && colcon build --base-paths src ${colcon_layout_args[*]} --parallel-workers ${WORKERS}"

printf '%s\n' "${BUILD_MODE}" > "${layout_marker}"

echo "Built ROS 2 ${ROS_DISTRO} (BUILD_MODE=${BUILD_MODE})."
