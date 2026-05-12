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

workspace=$(shell_quote "${ROS_WORKSPACE}")
run_as_ros_user "cd ${workspace} && . ${workspace}/venv/bin/activate && export CMAKE_BUILD_PARALLEL_LEVEL=${BUILD_JOBS} MAKEFLAGS=-j${BUILD_JOBS} && colcon build --base-paths src --symlink-install --parallel-workers ${WORKERS}"

echo "Built ROS 2 ${ROS_DISTRO}."
