#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

need_root "$@"
"${REPO_ROOT}/scripts/mount-rootfs.sh"

run_as_ros_user "cd ${ROS_WORKSPACE} && . ${ROS_WORKSPACE}/venv/bin/activate && . ${ROS_WORKSPACE}/install/local_setup.bash && ros2 --help >/dev/null"
run_as_ros_user "cd ${ROS_WORKSPACE} && . ${ROS_WORKSPACE}/venv/bin/activate && . ${ROS_WORKSPACE}/install/local_setup.bash && ros2 pkg executables demo_nodes_cpp | grep -q 'demo_nodes_cpp talker'"
run_as_ros_user "cd ${ROS_WORKSPACE} && . ${ROS_WORKSPACE}/venv/bin/activate && python -c 'import PyKDL'"

echo "ROS 2 ${ROS_DISTRO} smoke test passed."
