#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

need_root "$@"
"${REPO_ROOT}/scripts/mount-rootfs.sh"

if [[ ! -e "${ROOTFS_DIR}/etc/ros/rosdep/sources.list.d/20-default.list" ]]; then
	run_in_chroot rosdep init
fi
run_as_ros_user "${ROS_WORKSPACE}/venv/bin/rosdep update"

run_in_chroot /bin/bash -lc "cd ${ROS_WORKSPACE} && HOME=/home/${ROS_USER} ${ROS_WORKSPACE}/venv/bin/rosdep install --from-paths src --ignore-src -y --rosdistro ${ROS_DISTRO} --os=ubuntu:${UBUNTU_CODENAME} --skip-keys 'fastcdr rti-connext-dds-6.0.1 urdfdom_headers'"

echo "Installed ROS dependencies for ${ROS_DISTRO}."
