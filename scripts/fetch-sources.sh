#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

need_root "$@"
require_rootfs
require_chroot_executable "${ROS_WORKSPACE}/venv/bin/vcs" "Run scripts/provision-rootfs.sh first."
"${REPO_ROOT}/scripts/mount-rootfs.sh"

run_in_chroot mkdir -p "${ROS_WORKSPACE}/src"
run_in_chroot chown "${ROS_USER}:${ROS_USER}" "${ROS_WORKSPACE}" "${ROS_WORKSPACE}/src"

workspace=$(shell_quote "${ROS_WORKSPACE}")
repos_url=$(shell_quote "${ROS2_REPOS_URL}")
run_as_ros_user "cd ${workspace} && ${workspace}/venv/bin/vcs import --input ${repos_url} src"

if [[ -n "${ROS2_EXTRA_REPOS_FILE}" ]]; then
	[[ -f "${ROS2_EXTRA_REPOS_FILE}" ]] || die "Extra ROS 2 repos file does not exist: ${ROS2_EXTRA_REPOS_FILE}"

	extra_repos_chroot_path="/tmp/$(basename -- "${ROS2_EXTRA_REPOS_FILE}")"
	install -m 0644 "${ROS2_EXTRA_REPOS_FILE}" "${ROOTFS_DIR}${extra_repos_chroot_path}"

	extra_repos_url=$(shell_quote "${extra_repos_chroot_path}")
	run_as_ros_user "cd ${workspace} && ${workspace}/venv/bin/vcs import --input ${extra_repos_url} src"
fi

for extra_repos_url in ${ROS2_EXTRA_REPOS_URLS}; do
	extra_repos_url=$(shell_quote "${extra_repos_url}")
	run_as_ros_user "cd ${workspace} && ${workspace}/venv/bin/vcs import --input ${extra_repos_url} src"
done

echo "Fetched ROS 2 ${ROS_DISTRO} source manifests into ${ROS_WORKSPACE}/src."
