#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

need_root "$@"
require_rootfs
require_chroot_executable "${ROS_WORKSPACE}/venv/bin/python" "Run scripts/provision-rootfs.sh first."
require_chroot_path "${ROS_WORKSPACE}/install/local_setup.bash" "Run scripts/build-ros2.sh first."
"${REPO_ROOT}/scripts/mount-rootfs.sh"

workspace=$(shell_quote "${ROS_WORKSPACE}")
run_as_ros_user "cd ${workspace} && . ${workspace}/venv/bin/activate && . ${workspace}/install/local_setup.bash && ros2 --help >/dev/null"
run_as_ros_user "cd ${workspace} && . ${workspace}/venv/bin/activate && . ${workspace}/install/local_setup.bash && ros2 pkg executables demo_nodes_cpp | grep -q 'demo_nodes_cpp talker'"
run_as_ros_user "cd ${workspace} && . ${workspace}/venv/bin/activate && python -c 'import PyKDL'"

echo "ROS 2 ${ROS_DISTRO} smoke test passed."
