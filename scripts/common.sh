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
ROS_VERSION=${ROS_VERSION:-2}
ROS_PYTHON_VERSION=${ROS_PYTHON_VERSION:-3}
ROS2_REPOS_URL=${ROS2_REPOS_URL:-https://raw.githubusercontent.com/ros2/ros2/${ROS_DISTRO}/ros2.repos}
ROS2_EXTRA_REPOS_FILE=${ROS2_EXTRA_REPOS_FILE-${REPO_ROOT}/ros2-extra.repos}
ROS2_EXTRA_REPOS_URLS=${ROS2_EXTRA_REPOS_URLS:-}
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
    ROS_DISTRO="${ROS_DISTRO}" \
    ROS_VERSION="${ROS_VERSION}" \
    ROS_PYTHON_VERSION="${ROS_PYTHON_VERSION}" \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    "$@"
}

run_as_ros_user() {
  if [[ $# -ne 1 ]]; then
    die "run_as_ros_user expects a single shell-command string (got $#)."
  fi

  local command=$1
  local ros_distro ros_version ros_python_version

  ros_distro=$(shell_quote "${ROS_DISTRO}")
  ros_version=$(shell_quote "${ROS_VERSION}")
  ros_python_version=$(shell_quote "${ROS_PYTHON_VERSION}")

  run_in_chroot /usr/bin/su - "${ROS_USER}" -c "export ROS_DISTRO=${ros_distro} ROS_VERSION=${ros_version} ROS_PYTHON_VERSION=${ros_python_version}; ${command}"
}
