#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

need_root "$@"
"${REPO_ROOT}/scripts/umount-rootfs.sh" || true

if ! command -v zstd >/dev/null 2>&1; then
  echo "zstd is required on the host to create compressed rootfs archives." >&2
  exit 1
fi

# Excluding opt/ros2_ws/build from the archive (see the tar command below)
# is only safe if the install was built with copies, not symlinks. A
# --symlink-install build leaves install/ pointing back into build/ and src/,
# so dropping build/ would break the shipped install. scripts/build-ros2.sh
# records the mode it last used in .build_mode; refuse to pack a dev build.
marker="${ROOTFS_DIR}${ROS_WORKSPACE}/.build_mode"
if [[ -f "${marker}" ]]; then
  pack_mode=$(cat "${marker}")
  if [[ "${pack_mode}" != "release" ]]; then
    die "Rootfs was built with BUILD_MODE=${pack_mode}; install/ contains symlinks into build/, which the artifact excludes. Rebuild with BUILD_MODE=release (or rerun build_all.sh without --no-artifacts) before packing."
  fi
fi

# Compression level: override with ZSTD_LEVEL while iterating. Default is
# 19 (slow, tight) since pack-rootfs.sh only runs when producing the
# redistributable tarball. Drop to 3 for ~5x faster pack, ~10-20% larger
# archive while iterating on the pack script itself.
ZSTD_LEVEL=${ZSTD_LEVEL:-19}

mkdir -p "${REPO_ROOT}/artifacts"

build_date=$(date +%Y%m%d)
stem="ros2-${ROS_DISTRO}-${UBUNTU_CODENAME}-rootfs-${build_date}"
archive="${REPO_ROOT}/artifacts/${stem}.tar.zst"

# We want the tarball to extract to:
#
#   <stem>/
#   |-- rootfs/                                       (the chroot contents)
#   |-- ros2-chroot.sh -> rootfs/usr/local/bin/ros2-chroot.sh   (symlink)
#   `-- ARTIFACT_INFO                                 (plain-text metadata)
#
# The entry-point script lives *inside* the rootfs at /usr/local/bin/ros2-chroot.sh
# (installed by provision-rootfs.sh and refreshed below). The top-level entry
# is just a relative symlink, so there is a single source of truth and the
# script is also on $PATH once the recipient enters the chroot.
#
# We avoid copying the rootfs (5+ GB) by bind-mounting it read-only into a
# staging directory and tarring that staging directory in a single pass.
# A single archive (rather than two concatenated archives) is essential:
# `tar xf` stops at the first end-of-archive marker, so a concatenated stream
# would silently drop the helper files for recipients.
#
# We deliberately do NOT pass --one-file-system here: it would treat the bind
# mount as a separate filesystem and skip the rootfs contents. The umount
# performed at the top of this script guarantees that /proc, /sys, /dev and
# friends are not mounted inside ${ROOTFS_DIR}, so there is nothing to leak.
#
# We exclude the contents of rootfs/dev/ (debootstrap's static device nodes:
# null, zero, tty, console, ptmx, ...). They are character/block special files,
# so extracting them requires CAP_MKNOD, i.e. running `tar xf` as root. They
# are also useless in the artifact: cmd_mount in ros2-chroot.sh always
# bind-mounts the host's /dev over ${ROOTFS_DIR}/dev before chrooting. The
# rootfs/dev/ directory itself is kept (just empty) as the bind-mount target.

# Refresh the in-rootfs helper scripts so edits made since provisioning ship in
# the artifact.
install -m 0755 "${REPO_ROOT}/scripts/ros2-chroot.sh" \
  "${ROOTFS_DIR}/usr/local/bin/ros2-chroot.sh"
install -m 0755 "${REPO_ROOT}/scripts/ros2-config.sh" \
  "${ROOTFS_DIR}/usr/local/bin/ros2_config"

stage=$(mktemp -d -t ros2-pack-XXXXXX)
cleanup() {
  if mountpoint -q "${stage}/${stem}/rootfs" 2>/dev/null; then
    umount "${stage}/${stem}/rootfs" || umount -l "${stage}/${stem}/rootfs"
  fi
  rm -rf -- "${stage}"
}
trap cleanup EXIT

mkdir -p "${stage}/${stem}/rootfs"
mount --bind "${ROOTFS_DIR}" "${stage}/${stem}/rootfs"
mount -o remount,bind,ro "${stage}/${stem}/rootfs"

ln -s rootfs/usr/local/bin/ros2-chroot.sh "${stage}/${stem}/ros2-chroot.sh"

cat > "${stage}/${stem}/ARTIFACT_INFO" <<INFO
ros-distro:      ${ROS_DISTRO}
ubuntu-codename: ${UBUNTU_CODENAME}
build-date:      ${build_date}
host-arch:       $(dpkg --print-architecture 2>/dev/null || uname -m)
packed-by:       ros2-jazzy-noble-chroot/scripts/pack-rootfs.sh
INFO

cat > "${stage}/${stem}/README.md" <<README
# ros2-${ROS_DISTRO}-${UBUNTU_CODENAME}-rootfs (${build_date})

A self-contained, ready-to-run **ROS 2 ${ROS_DISTRO}** environment built from
source inside an **Ubuntu ${UBUNTU_CODENAME}** chroot. Use it on any modern
amd64 Linux host without polluting the host system or its Python.

## Layout

\`\`\`text
$(basename "${stem}")/
├── rootfs/                                       # the chroot contents
├── ros2-chroot.sh -> rootfs/usr/local/bin/ros2-chroot.sh
├── README.md                                     # this file
└── ARTIFACT_INFO                                 # build metadata
\`\`\`

## Host requirements

\`bash\`, \`sudo\`, \`tar\`, \`zstd\`, \`mount\`, \`chroot\`, \`findmnt\`.
No \`pip install\`, no PPAs, no clone of the build repository needed.

## First-time setup

Extract **as root** so the in-chroot file ownership (root for system files,
uid 1000 for the \`ros2\` user's workspace) survives:

\`\`\`bash
sudo tar xf $(basename "${archive}")
cd $(basename "${stem}")
sudo ./ros2-chroot.sh smoke-test     # verifies ros2 CLI, talker, PyKDL
\`\`\`

## Daily use

\`\`\`bash
cd /path/to/$(basename "${stem}") && sudo ./ros2-chroot.sh
\`\`\`

With no argument, \`ros2-chroot.sh\` mounts the chroot support filesystems
(\`/dev\`, \`/dev/pts\`, \`/proc\`, \`/sys\`, \`/run\`) and drops you into an
interactive bash as the \`ros2\` user with the ROS 2 environment sourced and
the workspace venv activated.

## Optional desktop tools

VS Code, Foxglove Desktop, and Firefox are not installed by default, keeping the
base artifact smaller. To add or remove them later, enter the chroot and run:

\`\`\`bash
ros2_config
\`\`\`

For scripted use, run \`ros2_config status\`, \`ros2_config install vscode\`,
\`ros2_config install foxglove\`, \`ros2_config install firefox\`, or the
matching \`remove\` commands. GUI launches need a host display;
\`ros2-chroot.sh\` forwards \`DISPLAY\` and \`XAUTHORITY\` when they are
available.

VS Code GitHub sign-in may not open your host browser automatically from inside
the chroot. Use the login URL or device code that VS Code displays and open it
in a host browser, or run \`ros2_config install firefox\` and use Firefox inside
the chroot. Firefox is installed from Mozilla's apt repository, not snap.

## Commands

| Command       | What it does                                                    |
|---------------|-----------------------------------------------------------------|
| (no arg)      | Alias for \`enter\`.                                            |
| \`enter\`     | Mount support filesystems, register a session, chroot in as \`ros2\`. Auto-unmounts on exit if no other sessions remain. |
| \`mount\`     | Mount the support filesystems only.                             |
| \`umount\`    | Unmount everything under \`rootfs/\`. Refuses if other sessions are active; pass \`--force\` to override. |
| \`smoke-test\`| Verify ros2 CLI, demo \`talker\`, and PyKDL.                    |
| \`status\`    | Show active chroot sessions (pid, tty, user, start time) and whether mounts are up. |
| \`info\`      | Print resolved paths and \`ARTIFACT_INFO\`.                     |
| \`help\`      | Show usage.                                                     |

## Multiple terminals & cleanup

The script tracks every active \`enter\` session in \`/run/ros2-chroot/<id>/\`
(host tmpfs, wiped on reboot). You can open the chroot in several terminals
simultaneously; \`mount\` is idempotent. When you exit, the script reports:

* **Last session out** -> support filesystems are unmounted automatically, and
  you are told the rootfs tree is now safe to \`rm -rf\`.
* **Other sessions still active** -> mounts are left in place; the message
  points you at \`ros2-chroot.sh status\` to see who's still in.

If a session crashed and left mounts behind, \`sudo ./ros2-chroot.sh umount\`
will refuse while it thinks sessions are active -- use \`umount --force\`.

## Environment overrides

| Variable        | Default                                | Purpose                            |
|-----------------|----------------------------------------|------------------------------------|
| \`ROOTFS_DIR\`  | \`<script dir>/rootfs\`                | Path to the chroot.                |
| \`ROS_USER\`    | \`ros2\`                               | User to su into inside the chroot. |
| \`ROS_WORKSPACE\`| \`/opt/ros2_ws\`                      | Workspace path inside the chroot.  |

## Notes

* The on-disk \`rootfs/dev/\` directory ships empty; the host's \`/dev\` is
  bind-mounted in at chroot time, so udev/devtmpfs nodes (input, video, gpu,
  serial, ...) are available inside the chroot.
* Network is shared with the host (no namespacing); \`resolv.conf\` is copied
  in at each \`mount\`/\`enter\`.
* The chroot is fully writable. To reset, re-extract the tarball.

Built by **ros2-jazzy-noble-chroot** — see
<https://github.com/pfavr/ros2-jazzy-noble-chroot> for the build
scripts and source.
README

tar --xattrs --acls --numeric-owner -I "zstd -T0 -${ZSTD_LEVEL}" \
    --exclude="${stem}/rootfs/dev/*" \
    --exclude="${stem}/rootfs/opt/ros2_ws/build" \
    --exclude="${stem}/rootfs/opt/ros2_ws/log" \
    --exclude="${stem}/rootfs/var/cache/apt/archives/*.deb" \
    --exclude="${stem}/rootfs/var/cache/apt/archives/partial/*" \
    --exclude="${stem}/rootfs/var/lib/apt/lists/*" \
    --exclude="${stem}/rootfs/root/.cache" \
    --exclude="${stem}/rootfs/home/ros2/.cache" \
    --exclude="${stem}/rootfs/tmp/*" \
    -cpf "${archive}" \
    -C "${stage}" "${stem}"

owner="${SUDO_UID:-$(id -u)}:${SUDO_GID:-$(id -g)}"
chown "${owner}" "${archive}"

echo "Wrote ${archive}"
echo "  size:           $(du -h "${archive}" | cut -f1)"
echo "  zstd level:     ${ZSTD_LEVEL} (override with ZSTD_LEVEL=3 for faster iteration)"
echo
echo "Recipient usage on a fresh host:"
echo "  sudo tar xf $(basename "${archive}")   # sudo preserves ownership of in-chroot files"
echo "  cd ${stem}"
echo "  sudo ./ros2-chroot.sh smoke-test   # one-time verification"
echo "  sudo ./ros2-chroot.sh               # enter the ROS shell (default action)"
