#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

need_root "$@"
"${REPO_ROOT}/scripts/mount-rootfs.sh"
"${REPO_ROOT}/scripts/install-rosdeps.sh"

WORKERS=${WORKERS:-4}
BUILD_JOBS=${BUILD_JOBS:-8}
run_as_ros_user "cd ${ROS_WORKSPACE} && . ${ROS_WORKSPACE}/venv/bin/activate && export CMAKE_BUILD_PARALLEL_LEVEL=${BUILD_JOBS} MAKEFLAGS=-j${BUILD_JOBS} && colcon build --base-paths src --symlink-install --parallel-workers ${WORKERS}"

echo "Built ROS 2 ${ROS_DISTRO}."
