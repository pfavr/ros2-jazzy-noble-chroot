#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

need_root "$@"
require_rootfs
"${REPO_ROOT}/scripts/mount-rootfs.sh"

run_in_chroot /usr/bin/env ROS_APT_SOURCE_VERSION="${ROS_APT_SOURCE_VERSION}" UBUNTU_CODENAME="${UBUNTU_CODENAME}" /bin/bash -lc '
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y locales sudo curl ca-certificates gnupg lsb-release
locale-gen en_US en_US.UTF-8
update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
apt-get update
if [[ -z "${ROS_APT_SOURCE_VERSION}" ]]; then
  ROS_APT_SOURCE_VERSION=$(curl -fsSL https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest | grep -F "tag_name" | awk -F"\"" "{print \$4; exit}")
fi
if [[ -z "${ROS_APT_SOURCE_VERSION}" ]]; then
  echo "Could not determine ros-apt-source release version." >&2
  exit 1
fi
curl -fsSL -o /tmp/ros2-apt-source.deb "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.${UBUNTU_CODENAME}_all.deb"
dpkg -i /tmp/ros2-apt-source.deb
apt-get update
apt-get upgrade -y
apt-get install -y \
  build-essential \
  cmake \
  git \
  ninja-build \
  pkg-config \
  python3-flake8-blind-except \
  python3-flake8-class-newline \
  python3-flake8-deprecated \
  python3-mypy \
  python3-pip \
  python3-pytest \
  python3-pytest-cov \
  python3-pytest-mock \
  python3-pytest-repeat \
  python3-pytest-rerunfailures \
  python3-pytest-runner \
  python3-pytest-timeout \
  python3-venv \
  ros-dev-tools
apt-get clean

# Workaround: Ubuntu Noble'"'"'s python3-pytest-repeat ships an incomplete
# /usr/lib/python3/dist-packages/pytest_repeat.egg-info/ directory (only
# entry_points.txt, no PKG-INFO) alongside the real pytest_repeat-*.dist-info.
# Setuptools'"'"' easy_install path scan flags it as
#   UserWarning: Unbuilt egg for pytest-repeat [unknown version]
# on every ament/colcon Python build. The .dist-info has the real metadata,
# so removing the stub is safe and silences ~90 spurious warnings per build.
rm -rf /usr/lib/python3/dist-packages/pytest_repeat.egg-info
'

if ! run_in_chroot getent group "${ROS_USER}" >/dev/null; then
  run_in_chroot groupadd --gid "${ROS_GID}" "${ROS_USER}"
fi

if ! run_in_chroot id -u "${ROS_USER}" >/dev/null 2>&1; then
  run_in_chroot useradd --uid "${ROS_UID}" --gid "${ROS_GID}" --create-home --shell /bin/bash "${ROS_USER}"
fi

run_in_chroot usermod -aG sudo "${ROS_USER}"
run_in_chroot mkdir -p "${ROS_WORKSPACE}"
run_in_chroot chown -R "${ROS_USER}:${ROS_USER}" "${ROS_WORKSPACE}" "/home/${ROS_USER}"

run_as_ros_user "python3 -m venv --clear --system-site-packages ${ROS_WORKSPACE}/venv"
# Pin setuptools below 70: setuptools >=70 escalates `tests_require` to a
# UserWarning and setuptools >=77 deprecates the legacy License classifiers,
# both of which are still used by many ROS 2 Jazzy Python packages upstream.
# Pinning below 70 keeps the build output clean without patching dozens of
# upstream setup.py / setup.cfg files. Setuptools 80 also drops easy_install,
# so the previous `<80` pin was already in this spirit; this just tightens it.
run_as_ros_user "${ROS_WORKSPACE}/venv/bin/python -m pip install --upgrade pip 'setuptools<70' wheel"
# --no-deps is deliberate: the venv is created with --system-site-packages, so colcon/vcstool/rosdep
# resolve their transitive deps (catkin_pkg, rosdistro, PyYAML, ...) against the apt-provided
# python3-* packages installed above. This avoids pulling in pip-built duplicates that can shadow
# the system versions PyKDL and other apt ROS bits expect.
run_as_ros_user "${ROS_WORKSPACE}/venv/bin/python -m pip install --ignore-installed --no-deps colcon-core vcstool rosdep"

if [[ ! -e "${ROOTFS_DIR}/etc/ros/rosdep/sources.list.d/20-default.list" ]]; then
  run_in_chroot rosdep init
fi
run_as_ros_user "${ROS_WORKSPACE}/venv/bin/rosdep update"

# Install the chroot-entry helper inside the rootfs itself, so it travels with
# the artifact and is also available on $PATH after entering the chroot.
install -m 0755 "${REPO_ROOT}/scripts/ros2-chroot.sh" \
  "${ROOTFS_DIR}/usr/local/bin/ros2-chroot.sh"

echo "Provisioned Ubuntu ${UBUNTU_CODENAME} rootfs for ROS 2 ${ROS_DISTRO}."
