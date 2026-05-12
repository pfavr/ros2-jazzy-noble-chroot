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
                Registers a session; on exit, auto-unmounts if no other
                sessions remain, otherwise leaves mounts up for them.
  mount         Bind-mount /dev /dev/pts /proc /sys /run into the rootfs.
  umount        Unmount chroot support filesystems under \$ROOTFS_DIR.
                Refuses if other sessions are still active; pass --force
                to override (e.g. after a crash).
  smoke-test    Mount, then verify ros2 CLI, demo binaries, and PyKDL.
  status        Show active chroot sessions and whether mounts are up.
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

# -----------------------------------------------------------------------------
# Session accounting
#
# Each `enter` registers a per-pid file under
#   /run/ros2-chroot/<id>/sessions/<pid>
# where <id> is a sha1 of the resolved rootfs path (lets multiple distinct
# rootfs trees coexist on the same host). `/run` is tmpfs, so the state is
# wiped on reboot and never pollutes the rootfs itself.
# -----------------------------------------------------------------------------

state_dir() {
  local rootfs_path id
  # Resolve the rootfs path if it exists; otherwise fall back to a lexical
  # normalisation so status/info still work before extraction.
  if [[ -d "${ROOTFS_DIR}" ]]; then
    rootfs_path=$(cd -P -- "${ROOTFS_DIR}" && pwd)
  else
    case "${ROOTFS_DIR}" in
      /*) rootfs_path=${ROOTFS_DIR} ;;
      *)  rootfs_path=${PWD}/${ROOTFS_DIR} ;;
    esac
  fi
  id=$(printf '%s' "${rootfs_path}" | sha1sum | cut -c1-12)
  echo "/run/ros2-chroot/${id}"
}

session_register() {
  local sd
  sd=$(state_dir)
  mkdir -p "${sd}/sessions"
  (cd -P -- "${ROOTFS_DIR}" && pwd) > "${sd}/rootfs-path"
  cat > "${sd}/sessions/$$" <<EOF
pid=$$
tty=$(tty 2>/dev/null || echo '?')
user=${SUDO_USER:-$(id -un)}
start=$(date -Iseconds 2>/dev/null || date)
EOF
}

session_unregister() {
  local sd
  sd=$(state_dir)
  rm -f "${sd}/sessions/$$"
}

# Print one path per live session file; reap files whose pid is gone.
session_list_live() {
  local sd f pid
  sd=$(state_dir)
  [[ -d "${sd}/sessions" ]] || return 0
  shopt -s nullglob
  for f in "${sd}/sessions"/*; do
    pid=$(basename "${f}")
    if kill -0 "${pid}" 2>/dev/null; then
      echo "${f}"
    else
      rm -f "${f}"
    fi
  done
  shopt -u nullglob
}

session_count_live() {
  session_list_live | wc -l
}

# Are any of the support filesystems currently mounted under the rootfs?
chroot_is_mounted() {
  [[ -d "${ROOTFS_DIR}" ]] || return 1
  local rootfs_path
  rootfs_path=$(cd -P -- "${ROOTFS_DIR}" && pwd)
  findmnt -rn -o TARGET \
    | awk -v r="${rootfs_path}" '($0 == r) || (substr($0, 1, length(r) + 1) == r "/")' \
    | grep -q .
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
  local force=0
  if [[ "${1:-}" == "--force" ]]; then
    force=1
    shift
  fi

  if [[ ! -d "${ROOTFS_DIR}" ]]; then
    echo "No rootfs at ${ROOTFS_DIR}, nothing to do."
    return 0
  fi

  local live
  live=$(session_count_live)
  if (( live > 0 )) && (( force == 0 )); then
    echo "Refusing to unmount: ${live} active chroot session(s) still in use." >&2
    echo "Run '${SCRIPT_NAME} status' to see them, or 'umount --force' to override." >&2
    return 1
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

# Called from cmd_enter's EXIT trap after the chroot returns.
# - Unregisters this pid.
# - If no other sessions are alive, unmounts the support filesystems and tells
#   the user the rootfs tree is now safe to delete.
# - Otherwise prints the remaining sessions so it's obvious why mounts stay up.
enter_cleanup() {
  session_unregister
  local live
  live=$(session_count_live)
  echo
  if (( live == 0 )); then
    echo "[ros2-chroot] last session ended; unmounting support filesystems..."
    cmd_umount
    if chroot_is_mounted; then
      echo "[ros2-chroot] warning: some mounts could not be released." >&2
    else
      echo "[ros2-chroot] all mounts released. The rootfs tree at"
      echo "              ${ROOTFS_DIR}"
      echo "              is now safe to 'rm -rf' if you wish to delete it."
    fi
  else
    echo "[ros2-chroot] ${live} other chroot session(s) still active; mounts left in place."
    echo "[ros2-chroot] run '${SCRIPT_NAME} status' for details."
  fi
}

cmd_enter() {
  cmd_mount
  session_register
  trap enter_cleanup EXIT
  # Deliberately no 'exec': we need to retain the parent shell so the EXIT
  # trap runs after the chroot returns. Suppress set -e on the chroot exit
  # code so a non-zero shell exit (e.g. Ctrl-D after a failed command) still
  # lets cleanup print its summary.
  /usr/sbin/chroot "${ROOTFS_DIR}" /usr/bin/su - "${ROS_USER}" -c \
    "cd ${ROS_WORKSPACE} && exec bash --rcfile <(printf '%s\n' 'source ${ROS_WORKSPACE}/venv/bin/activate' 'if [[ -f ${ROS_WORKSPACE}/install/local_setup.bash ]]; then source ${ROS_WORKSPACE}/install/local_setup.bash; fi' 'cd ${ROS_WORKSPACE}')" \
    || true
}

cmd_smoke_test() {
  cmd_mount
  /usr/sbin/chroot "${ROOTFS_DIR}" /usr/bin/su - "${ROS_USER}" -c \
    "set -e; cd ${ROS_WORKSPACE} && . venv/bin/activate && . install/local_setup.bash && ros2 --help >/dev/null && ros2 pkg executables demo_nodes_cpp | grep -q 'demo_nodes_cpp talker' && { timeout --preserve-status 3 ros2 run demo_nodes_cpp talker >/dev/null 2>&1; rc=\$?; [[ \$rc -eq 0 || \$rc -eq 124 || \$rc -eq 143 ]]; } && python -c 'import PyKDL'"
  echo "Smoke test passed."
}

cmd_status() {
  local sd resolved
  sd=$(state_dir)
  if [[ -d "${ROOTFS_DIR}" ]]; then
    resolved=$(cd -P -- "${ROOTFS_DIR}" && pwd)
  else
    resolved="${ROOTFS_DIR} (not present)"
  fi
  echo "Rootfs:     ${resolved}"
  echo "State dir:  ${sd}"
  if chroot_is_mounted; then
    echo "Mounts:     active"
  else
    echo "Mounts:     none"
  fi
  local -a live
  mapfile -t live < <(session_list_live)
  echo "Sessions:   ${#live[@]}"
  if (( ${#live[@]} > 0 )); then
    echo
    printf '  %-8s %-12s %-12s %s\n' PID TTY USER STARTED
    local f pid tty user start
    for f in "${live[@]}"; do
      pid=""; tty=""; user=""; start=""
      # shellcheck disable=SC1090
      source "${f}"
      printf '  %-8s %-12s %-12s %s\n' "${pid}" "${tty##*/}" "${user}" "${start}"
    done
  fi
  if ! chroot_is_mounted && (( ${#live[@]} == 0 )) && [[ -d "${ROOTFS_DIR}" ]]; then
    echo
    echo "The rootfs tree is idle; 'rm -rf ${ROOTFS_DIR}' (or its parent dir) is safe."
  fi
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
    umount)         need_root "${cmd}" "$@"; cmd_umount "$@" ;;
    smoke-test)     need_root "${cmd}" "$@"; cmd_smoke_test ;;
    status)         need_root "${cmd}" "$@"; cmd_status ;;
    info)           cmd_info ;;
    help|-h|--help) usage ;;
    *)              usage >&2; exit 2 ;;
  esac
}

main "$@"
