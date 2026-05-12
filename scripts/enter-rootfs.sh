#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

need_root "$@"
"${REPO_ROOT}/scripts/mount-rootfs.sh"

if [[ "${1:-}" == "--ros-shell" ]]; then
  exec /usr/sbin/chroot "${ROOTFS_DIR}" /usr/bin/su - "${ROS_USER}" -c "cd ${ROS_WORKSPACE} && exec bash --rcfile <(printf '%s\n' 'source ${ROS_WORKSPACE}/venv/bin/activate' 'if [[ -f ${ROS_WORKSPACE}/install/local_setup.bash ]]; then source ${ROS_WORKSPACE}/install/local_setup.bash; fi' 'cd ${ROS_WORKSPACE}')"
fi

exec /usr/sbin/chroot "${ROOTFS_DIR}" /usr/bin/su - "${ROS_USER}"
