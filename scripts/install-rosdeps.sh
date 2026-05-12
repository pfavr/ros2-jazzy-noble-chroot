#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

need_root "$@"
require_rootfs
require_chroot_executable "${ROS_WORKSPACE}/venv/bin/rosdep" "Run scripts/provision-rootfs.sh first."
require_chroot_path "${ROS_WORKSPACE}/src" "Run scripts/fetch-sources.sh first."
"${REPO_ROOT}/scripts/mount-rootfs.sh"

if [[ ! -e "${ROOTFS_DIR}/etc/ros/rosdep/sources.list.d/20-default.list" ]]; then
	run_in_chroot rosdep init
fi
run_as_ros_user "${ROS_WORKSPACE}/venv/bin/rosdep update"

workspace=$(shell_quote "${ROS_WORKSPACE}")
ros_home=$(shell_quote "/home/${ROS_USER}")
ros_distro=$(shell_quote "${ROS_DISTRO}")
ubuntu_codename=$(shell_quote "${UBUNTU_CODENAME}")
skip_keys=$(shell_quote "${ROSDEP_SKIP_KEYS}")
run_in_chroot /bin/bash -lc "cd ${workspace} && HOME=${ros_home} ${workspace}/venv/bin/rosdep install --from-paths src --ignore-src -y --rosdistro ${ros_distro} --os=ubuntu:${ubuntu_codename} --skip-keys ${skip_keys}"

echo "Installed ROS dependencies for ${ROS_DISTRO}."
