#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ROOTFS_DIR=${ROOTFS_DIR:-"${REPO_ROOT}/rootfs"}
ROS_WORKSPACE=${ROS_WORKSPACE:-/opt/ros2_ws}
ROS_USER=${ROS_USER:-ros2}
ROS_UID=${ROS_UID:-1000}
ROS_GID=${ROS_GID:-1000}
UBUNTU_CODENAME=${UBUNTU_CODENAME:-noble}
UBUNTU_MIRROR=${UBUNTU_MIRROR:-http://archive.ubuntu.com/ubuntu}
ROS_DISTRO=${ROS_DISTRO:-jazzy}
ROS2_REPOS_URL=${ROS2_REPOS_URL:-https://raw.githubusercontent.com/ros2/ros2/${ROS_DISTRO}/ros2.repos}
ROSDEP_SKIP_KEYS=${ROSDEP_SKIP_KEYS:-fastcdr rti-connext-dds-6.0.1 urdfdom_headers}
ROS_APT_SOURCE_VERSION=${ROS_APT_SOURCE_VERSION:-}
DEBOOTSTRAP=${DEBOOTSTRAP:-/usr/sbin/debootstrap}

die() {
  echo "error: $*" >&2
  exit 1
}

need_root() {
  if [[ ${EUID} -ne 0 ]]; then
    exec sudo -E "$0" "$@"
  fi
}

rootfs_exists() {
  [[ -d "${ROOTFS_DIR}" && -e "${ROOTFS_DIR}/etc/os-release" ]]
}

require_rootfs() {
  rootfs_exists || die "Rootfs does not exist at ${ROOTFS_DIR}. Run scripts/create-rootfs.sh first."
}

require_chroot_path() {
  local path=$1
  local hint=$2

  [[ -e "${ROOTFS_DIR}${path}" ]] || die "Missing ${path} inside the rootfs. ${hint}"
}

require_chroot_executable() {
  local path=$1
  local hint=$2

  [[ -x "${ROOTFS_DIR}${path}" ]] || die "Missing executable ${path} inside the rootfs. ${hint}"
}

shell_quote() {
  printf '%q' "$1"
}

run_in_chroot() {
  /usr/sbin/chroot "${ROOTFS_DIR}" /usr/bin/env -i \
    HOME=/root \
    TERM="${TERM:-xterm-256color}" \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    "$@"
}

run_as_ros_user() {
  run_in_chroot /usr/bin/su - "${ROS_USER}" -c "$*"
}
