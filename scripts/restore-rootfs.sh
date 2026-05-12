#!/usr/bin/env bash
# Self-contained companion to a ros2-jazzy-noble-rootfs-*.tar.zst archive.
#
# scripts/pack-rootfs.sh installs a copy of this file next to each archive
# under artifacts/, named <archive-stem>.restore.sh. Distribute the two
# files together; the recipient only needs zstd, tar, sudo, and chroot
# support on the host. No clone of ros2-jazzy-noble-chroot is required.
#
# Quick start on a fresh host:
#   chmod +x ros2-jazzy-noble-rootfs-YYYYMMDD.restore.sh
#   ./ros2-jazzy-noble-rootfs-YYYYMMDD.restore.sh unpack
#   ./ros2-jazzy-noble-rootfs-YYYYMMDD.restore.sh smoke-test
#   ./ros2-jazzy-noble-rootfs-YYYYMMDD.restore.sh enter
#
# Override the destination or chroot identity with environment variables:
#   ROOTFS_DIR=/srv/ros2-rootfs ./...restore.sh unpack
#   ROS_USER=ros2 ROS_WORKSPACE=/opt/ros2_ws ./...restore.sh enter
set -euo pipefail

SCRIPT_PATH=$(readlink -f -- "${BASH_SOURCE[0]}")
SCRIPT_DIR=$(dirname -- "${SCRIPT_PATH}")
SCRIPT_NAME=$(basename -- "${SCRIPT_PATH}")

ROOTFS_DIR=${ROOTFS_DIR:-${SCRIPT_DIR}/rootfs}
ROS_USER=${ROS_USER:-ros2}
ROS_WORKSPACE=${ROS_WORKSPACE:-/opt/ros2_ws}

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} <command> [archive]

Commands:
  unpack [ARCHIVE]   Extract ARCHIVE into \$ROOTFS_DIR (default: ${ROOTFS_DIR}).
                     If ARCHIVE is omitted, the script auto-detects a sibling
                     *.tar.zst file with the matching basename.
  mount              Bind-mount /dev /dev/pts /proc /sys /run into the rootfs.
  umount             Unmount chroot support filesystems under \$ROOTFS_DIR.
  enter              Mount and chroot in as \$ROS_USER with the ROS env sourced.
  smoke-test         Mount, then verify ros2 CLI, demo binaries, and PyKDL.
  help               Show this help.

Environment overrides:
  ROOTFS_DIR        Where to extract / find the rootfs (default: ./rootfs next to this script).
  ROS_USER          Internal chroot user (default: ros2).
  ROS_WORKSPACE     Workspace path inside the chroot (default: /opt/ros2_ws).
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

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command '$1' not found on host."
}

discover_archive() {
  # Prefer a sibling with the same basename stem as this script.
  local stem="${SCRIPT_NAME%.restore.sh}"
  local guess="${SCRIPT_DIR}/${stem}.tar.zst"
  if [[ -f "${guess}" ]]; then
    printf '%s\n' "${guess}"
    return 0
  fi
  # Fallback: if there's exactly one *.tar.zst next to the script, use it.
  shopt -s nullglob
  local siblings=("${SCRIPT_DIR}"/*.tar.zst)
  shopt -u nullglob
  if [[ ${#siblings[@]} -eq 1 ]]; then
    printf '%s\n' "${siblings[0]}"
    return 0
  fi
  return 1
}

cmd_unpack() {
  local archive=${1:-}
  if [[ -z "${archive}" ]]; then
    archive=$(discover_archive) || die "no archive specified and no sibling *.tar.zst found next to ${SCRIPT_NAME}."
  fi
  [[ -f "${archive}" ]] || die "archive not found: ${archive}"
  require_cmd zstd
  require_cmd tar
  if [[ -e "${ROOTFS_DIR}/etc/os-release" ]]; then
    die "${ROOTFS_DIR} already contains a rootfs. Move it aside or set ROOTFS_DIR=/somewhere/else."
  fi
  mkdir -p "${ROOTFS_DIR}"
  tar --xattrs --acls --numeric-owner -I zstd -xpf "${archive}" -C "${ROOTFS_DIR}"
  cp --remove-destination /etc/resolv.conf "${ROOTFS_DIR}/etc/resolv.conf"
  echo "Unpacked ${archive} into ${ROOTFS_DIR}"
}

require_rootfs() {
  [[ -e "${ROOTFS_DIR}/etc/os-release" ]] || die "no rootfs at ${ROOTFS_DIR}. Run '${SCRIPT_NAME} unpack' first."
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

main() {
  local cmd=${1:-help}
  shift || true
  case "${cmd}" in
    unpack)       need_root "${cmd}" "$@"; cmd_unpack "$@" ;;
    mount)        need_root "${cmd}" "$@"; cmd_mount ;;
    umount)       need_root "${cmd}" "$@"; cmd_umount ;;
    enter)        need_root "${cmd}" "$@"; cmd_enter ;;
    smoke-test)   need_root "${cmd}" "$@"; cmd_smoke_test ;;
    help|-h|--help) usage ;;
    *) usage >&2; exit 2 ;;
  esac
}

main "$@"
