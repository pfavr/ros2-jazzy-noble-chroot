#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

need_root "$@"
"${REPO_ROOT}/scripts/umount-rootfs.sh" || true

if ! command -v zstd >/dev/null 2>&1; then
	echo "zstd is required on the host to create compressed rootfs archives." >&2
	exit 1
fi

mkdir -p "${REPO_ROOT}/artifacts"
archive="${REPO_ROOT}/artifacts/ros2-${ROS_DISTRO}-${UBUNTU_CODENAME}-rootfs-$(date +%Y%m%d).tar.zst"
tar --xattrs --acls --numeric-owner --one-file-system -I 'zstd -T0 -19' -cpf "${archive}" -C "${ROOTFS_DIR}" .
chown "${SUDO_UID:-$(id -u)}:${SUDO_GID:-$(id -g)}" "${archive}"

echo "Wrote ${archive}"
