#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

need_root "$@"
require_rootfs
require_chroot_path "/home/${ROS_USER}" "Run scripts/provision-rootfs.sh first."
"${REPO_ROOT}/scripts/mount-rootfs.sh"

if [[ "${1:-}" == "--ros-shell" ]]; then
  require_chroot_executable "${ROS_WORKSPACE}/venv/bin/python" "Run scripts/provision-rootfs.sh first."
  workspace=$(shell_quote "${ROS_WORKSPACE}")
  exec /usr/sbin/chroot "${ROOTFS_DIR}" /usr/bin/su - "${ROS_USER}" -c "cd ${workspace} && exec bash --rcfile <(printf '%s\n' 'source ${ROS_WORKSPACE}/venv/bin/activate' 'if [[ -f ${ROS_WORKSPACE}/install/local_setup.bash ]]; then source ${ROS_WORKSPACE}/install/local_setup.bash; fi' 'cd ${ROS_WORKSPACE}')"
fi

exec /usr/sbin/chroot "${ROOTFS_DIR}" /usr/bin/su - "${ROS_USER}"
