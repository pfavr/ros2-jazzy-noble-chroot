#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

need_root "$@"
"${REPO_ROOT}/scripts/mount-rootfs.sh"

run_in_chroot mkdir -p "${ROS_WORKSPACE}/src"
run_in_chroot chown -R "${ROS_USER}:${ROS_USER}" "${ROS_WORKSPACE}"

run_as_ros_user "cd ${ROS_WORKSPACE} && ${ROS_WORKSPACE}/venv/bin/vcs import --input https://raw.githubusercontent.com/ros2/ros2/${ROS_DISTRO}/ros2.repos src"

echo "Fetched ROS 2 ${ROS_DISTRO} sources into ${ROS_WORKSPACE}/src."
