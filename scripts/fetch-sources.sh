#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

need_root "$@"
require_rootfs
require_chroot_executable "${ROS_WORKSPACE}/venv/bin/vcs" "Run scripts/provision-rootfs.sh first."
"${REPO_ROOT}/scripts/mount-rootfs.sh"

run_in_chroot mkdir -p "${ROS_WORKSPACE}/src"
run_in_chroot chown -R "${ROS_USER}:${ROS_USER}" "${ROS_WORKSPACE}"

workspace=$(shell_quote "${ROS_WORKSPACE}")
repos_url=$(shell_quote "${ROS2_REPOS_URL}")
run_as_ros_user "cd ${workspace} && ${workspace}/venv/bin/vcs import --input ${repos_url} src"

echo "Fetched ROS 2 ${ROS_DISTRO} sources into ${ROS_WORKSPACE}/src."
