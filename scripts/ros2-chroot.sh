#!/usr/bin/env bash
# Enter and manage a ros2-jazzy-noble chroot.
#
# This script lives inside the rootfs at /usr/local/bin/ros2-chroot.sh, and
# a packed artifact exposes it via a top-level symlink:
#
#   ros2-jazzy-noble-rootfs-YYYYMMDD/
#   |-- rootfs/...usr/local/bin/ros2-chroot.sh   (this file)
#   `-- ros2-chroot.sh -> rootfs/usr/local/bin/ros2-chroot.sh
#
# After `tar xf ros2-jazzy-noble-rootfs-YYYYMMDD.tar.zst`, cd into the
# extracted directory and run `sudo ./ros2-chroot.sh`. With no argument it
# enters an interactive ROS-ready shell -- the operation you typically want
# after a reboot or in a fresh terminal.
#
# Recipient requirements: bash, sudo, mount, chroot, findmnt. No clone of
# the ros2-jazzy-noble-chroot repository is needed.
set -euo pipefail

# Resolve SCRIPT_DIR from the invocation path WITHOUT following symlinks.
# In a packed artifact the user invokes the top-level symlink at <stem>/ros2-chroot.sh,
# which points into the rootfs. We want SCRIPT_DIR to be <stem>/ (so that
# ${SCRIPT_DIR}/rootfs resolves correctly), not the symlink's target.
SCRIPT_SRC=${BASH_SOURCE[0]}
SCRIPT_DIR=$(cd -- "$(dirname -- "${SCRIPT_SRC}")" && pwd)
SCRIPT_NAME=$(basename -- "${SCRIPT_SRC}")
SCRIPT_PATH="${SCRIPT_DIR}/${SCRIPT_NAME}"

ROOTFS_DIR=${ROOTFS_DIR:-${SCRIPT_DIR}/rootfs}
ROS_USER=${ROS_USER:-ros2}
ROS_WORKSPACE=${ROS_WORKSPACE:-/opt/ros2_ws}

usage() {
  cat <<EOF
Usage: sudo ./${SCRIPT_NAME} [command]

With no command, ${SCRIPT_NAME} enters an interactive ROS-ready shell inside
the chroot. This is the operation you want after a reboot or in a fresh
terminal.

Commands:
  enter         (default) Mount and chroot in as \$ROS_USER with the ROS env sourced.
  mount         Bind-mount /dev /dev/pts /proc /sys /run into the rootfs.
  umount        Unmount chroot support filesystems under \$ROOTFS_DIR.
  smoke-test    Mount, then verify ros2 CLI, demo binaries, and PyKDL.
  info          Show artifact metadata and the resolved rootfs path.
  help          Show this help.

Environment overrides:
  ROOTFS_DIR    Path to the rootfs (default: \${SCRIPT_DIR}/rootfs).
  ROS_USER      Internal chroot user (default: ros2).
  ROS_WORKSPACE Workspace path inside the chroot (default: /opt/ros2_ws).
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

need_root() {
  if [[ ${EUID} -ne 0 ]]; then
    exec sudo -E "${SCRIPT_PATH}" "$@"
  fi
}

require_rootfs() {
  [[ -e "${ROOTFS_DIR}/etc/os-release" ]] \
    || die "no rootfs at ${ROOTFS_DIR}. Did the tarball extract cleanly?"
}

cmd_mount() {
  require_rootfs
  mkdir -p "${ROOTFS_DIR}/dev" "${ROOTFS_DIR}/dev/pts" "${ROOTFS_DIR}/proc" "${ROOTFS_DIR}/sys" "${ROOTFS_DIR}/run"
  mountpoint -q "${ROOTFS_DIR}/dev"     || mount --bind /dev     "${ROOTFS_DIR}/dev"
  mountpoint -q "${ROOTFS_DIR}/dev/pts" || mount --bind /dev/pts "${ROOTFS_DIR}/dev/pts"
  mountpoint -q "${ROOTFS_DIR}/proc"    || mount -t proc  proc   "${ROOTFS_DIR}/proc"
  mountpoint -q "${ROOTFS_DIR}/sys"     || mount -t sysfs sysfs  "${ROOTFS_DIR}/sys"
  mountpoint -q "${ROOTFS_DIR}/run"     || mount --bind /run     "${ROOTFS_DIR}/run"
  cp --remove-destination /etc/resolv.conf "${ROOTFS_DIR}/etc/resolv.conf"
}

cmd_umount() {
  if [[ ! -d "${ROOTFS_DIR}" ]]; then
    echo "No rootfs at ${ROOTFS_DIR}, nothing to do."
    return 0
  fi
  local rootfs_path
  rootfs_path=$(cd -P -- "${ROOTFS_DIR}" && pwd)
  local -a mountpoints=()
  mapfile -t mountpoints < <(
    findmnt -rn -o TARGET \
      | awk -v root="${rootfs_path}" '($0 == root) || (substr($0, 1, length(root) + 1) == root "/") { print length($0) "\t" $0 }' \
      | sort -rn \
      | cut -f2-
  )
  for mp in "${mountpoints[@]}"; do
    if mountpoint -q "${mp}"; then
      umount "${mp}" || umount -l "${mp}"
    fi
  done
}

cmd_enter() {
  cmd_mount
  exec /usr/sbin/chroot "${ROOTFS_DIR}" /usr/bin/su - "${ROS_USER}" -c \
    "cd ${ROS_WORKSPACE} && exec bash --rcfile <(printf '%s\n' 'source ${ROS_WORKSPACE}/venv/bin/activate' 'if [[ -f ${ROS_WORKSPACE}/install/local_setup.bash ]]; then source ${ROS_WORKSPACE}/install/local_setup.bash; fi' 'cd ${ROS_WORKSPACE}')"
}

cmd_smoke_test() {
  cmd_mount
  /usr/sbin/chroot "${ROOTFS_DIR}" /usr/bin/su - "${ROS_USER}" -c \
    "set -e; cd ${ROS_WORKSPACE} && . venv/bin/activate && . install/local_setup.bash && ros2 --help >/dev/null && ros2 pkg executables demo_nodes_cpp | grep -q 'demo_nodes_cpp talker' && { timeout --preserve-status 3 ros2 run demo_nodes_cpp talker >/dev/null 2>&1; rc=\$?; [[ \$rc -eq 0 || \$rc -eq 124 || \$rc -eq 143 ]]; } && python -c 'import PyKDL'"
  echo "Smoke test passed."
}

cmd_info() {
  echo "Script path:    ${SCRIPT_PATH}"
  echo "Rootfs path:    ${ROOTFS_DIR}"
  if [[ -f "${SCRIPT_DIR}/ARTIFACT_INFO" ]]; then
    echo "--- ARTIFACT_INFO ---"
    cat "${SCRIPT_DIR}/ARTIFACT_INFO"
  fi
}

main() {
  local cmd=${1:-enter}
  shift || true
  case "${cmd}" in
    enter)          need_root "${cmd}" "$@"; cmd_enter ;;
    mount)          need_root "${cmd}" "$@"; cmd_mount ;;
    umount)         need_root "${cmd}" "$@"; cmd_umount ;;
    smoke-test)     need_root "${cmd}" "$@"; cmd_smoke_test ;;
    info)           cmd_info ;;
    help|-h|--help) usage ;;
    *)              usage >&2; exit 2 ;;
  esac
}

main "$@"
