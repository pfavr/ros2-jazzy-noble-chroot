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

# Ship a self-contained companion script next to the archive so the recipient
# can unpack, mount, enter, and smoke-test the rootfs without cloning this repo.
restore_script="${archive%.tar.zst}.restore.sh"
install -m 0755 "${REPO_ROOT}/scripts/restore-rootfs.sh" "${restore_script}"

owner="${SUDO_UID:-$(id -u)}:${SUDO_GID:-$(id -g)}"
chown "${owner}" "${archive}" "${restore_script}"

echo "Wrote ${archive}"
echo "Wrote ${restore_script}"
