#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

usage() {
  cat <<USAGE
Usage: sudo $0

Create Docker-friendly artifacts from the built rootfs:

  artifacts/ros2-${ROS_DISTRO}-${UBUNTU_CODENAME}-docker.tar.zst
  artifacts/ros2-${ROS_DISTRO}-${UBUNTU_CODENAME}-docker.Dockerfile
  artifacts/ros2-${ROS_DISTRO}-${UBUNTU_CODENAME}-docker-run.sh

The tarball contains the rootfs contents at archive root, plus a Docker
entrypoint at /usr/local/bin/ros2-docker-entrypoint.sh. It is suitable for
either:

  zstd -dc ...tar.zst | docker import ...

or building with the generated Dockerfile.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

need_root "$@"
require_rootfs
"${REPO_ROOT}/scripts/umount-rootfs.sh" || true

if ! command -v zstd >/dev/null 2>&1; then
  die "zstd is required on the host to create Docker rootfs archives."
fi

marker="${ROOTFS_DIR}${ROS_WORKSPACE}/.build_mode"
if [[ -f "${marker}" ]]; then
  pack_mode=$(cat "${marker}")
  if [[ "${pack_mode}" != "release" ]]; then
    die "Rootfs was built with BUILD_MODE=${pack_mode}; install/ may contain symlinks into build/. Rebuild with BUILD_MODE=release before packing Docker artifacts."
  fi
fi

ZSTD_LEVEL=${ZSTD_LEVEL:-19}
image_name="ros2-${ROS_DISTRO}-${UBUNTU_CODENAME}:sourcebuilt"
archive_name="ros2-${ROS_DISTRO}-${UBUNTU_CODENAME}-docker.tar.zst"
dockerfile_name="ros2-${ROS_DISTRO}-${UBUNTU_CODENAME}-docker.Dockerfile"
run_script_name="ros2-${ROS_DISTRO}-${UBUNTU_CODENAME}-docker-run.sh"
archive="${REPO_ROOT}/artifacts/${archive_name}"
dockerfile="${REPO_ROOT}/artifacts/${dockerfile_name}"
run_script="${REPO_ROOT}/artifacts/${run_script_name}"

mkdir -p "${REPO_ROOT}/artifacts"

# Refresh the in-rootfs helper script that is still useful inside a writable
# container for optional desktop tools. The Docker entrypoint itself is injected
# through the temporary overlay below, so the chroot rootfs remains usable as-is.
install -m 0755 "${REPO_ROOT}/scripts/ros2-config.sh" \
  "${ROOTFS_DIR}/usr/local/bin/ros2_config"

stage=$(mktemp -d -t ros2-docker-pack-XXXXXX)
cleanup() {
  if mountpoint -q "${stage}/rootfs" 2>/dev/null; then
    umount "${stage}/rootfs" || umount -l "${stage}/rootfs"
  fi
  rm -rf -- "${stage}"
}
trap cleanup EXIT

mkdir -p "${stage}/rootfs" "${stage}/overlay/usr/local/bin"
mount --bind "${ROOTFS_DIR}" "${stage}/rootfs"
mount -o remount,bind,ro "${stage}/rootfs"

cat > "${stage}/overlay/usr/local/bin/ros2-docker-entrypoint.sh" <<'ENTRYPOINT'
#!/usr/bin/env bash
set -eo pipefail

if [[ -r /opt/ros2_ws/venv/bin/activate ]]; then
  # shellcheck disable=SC1091
  source /opt/ros2_ws/venv/bin/activate
fi

if [[ -r /opt/ros2_ws/install/local_setup.bash ]]; then
  # shellcheck disable=SC1091
  source /opt/ros2_ws/install/local_setup.bash
fi

cd /opt/ros2_ws 2>/dev/null || cd /

if [[ $# -eq 0 ]]; then
  set -- bash
fi

exec "$@"
ENTRYPOINT
chmod 0755 "${stage}/overlay/usr/local/bin/ros2-docker-entrypoint.sh"

tar --xattrs --acls --numeric-owner -I "zstd -T0 -${ZSTD_LEVEL}" \
    --exclude='./dev/*' \
    --exclude='./proc/*' \
    --exclude='./sys/*' \
    --exclude='./run/*' \
    --exclude='./tmp/*' \
    --exclude='./opt/ros2_ws/build' \
    --exclude='./opt/ros2_ws/log' \
    --exclude='./var/cache/apt/archives/*.deb' \
    --exclude='./var/cache/apt/archives/partial/*' \
    --exclude='./var/lib/apt/lists/*' \
    --exclude='./root/.cache' \
    --exclude='./home/ros2/.cache' \
    -cpf "${archive}" \
    -C "${stage}/rootfs" . \
    -C "${stage}/overlay" .

cat > "${dockerfile}" <<DOCKERFILE
# syntax=docker/dockerfile:1
# Build from the rootfs archive produced by scripts/pack-docker.sh.
# Keep this Dockerfile next to ${archive_name}, then run:
#
#   docker build -f ${dockerfile_name} -t ${image_name} .
#
# The import path is faster and does not need a build-time apt install:
#
#   zstd -dc ${archive_name} | docker import \\
#     --change 'ENTRYPOINT ["/usr/local/bin/ros2-docker-entrypoint.sh"]' \\
#     --change 'CMD ["bash"]' \\
#     --change 'USER ros2' \\
#     --change 'WORKDIR ${ROS_WORKSPACE}' \\
#     --change 'ENV ROS_DISTRO=${ROS_DISTRO} ROS_VERSION=${ROS_VERSION} ROS_PYTHON_VERSION=${ROS_PYTHON_VERSION} LANG=C.UTF-8 LC_ALL=C.UTF-8' \\
#     - ${image_name}

FROM ubuntu:24.04 AS extract
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tar zstd \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /work
COPY ${archive_name} /work/rootfs.tar.zst
RUN mkdir /rootfs \
    && zstd -dc /work/rootfs.tar.zst | tar -xpf - -C /rootfs

FROM scratch
COPY --from=extract /rootfs/ /
ENV ROS_DISTRO=${ROS_DISTRO} \
    ROS_VERSION=${ROS_VERSION} \
    ROS_PYTHON_VERSION=${ROS_PYTHON_VERSION} \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8
USER ros2
WORKDIR ${ROS_WORKSPACE}
ENTRYPOINT ["/usr/local/bin/ros2-docker-entrypoint.sh"]
CMD ["bash"]
DOCKERFILE

cat > "${run_script}" <<RUNSCRIPT
#!/usr/bin/env bash
set -euo pipefail

IMAGE="\${ROS2_DOCKER_IMAGE:-${image_name}}"

caller_home="\${HOME:-}"
if [[ \${EUID} -eq 0 && -n "\${SUDO_USER:-}" ]]; then
  caller_home=\$(getent passwd "\${SUDO_USER}" | cut -d: -f6)
fi

docker_tty=()
if [[ -t 0 && -t 1 ]]; then
  docker_tty=(-it)
else
  docker_tty=(-i)
fi

env_args=()
for name in ROS_DOMAIN_ID RMW_IMPLEMENTATION; do
  if [[ -n "\${!name:-}" ]]; then
    env_args+=(-e "\${name}=\${!name}")
  fi
done

security_args=()
case "\${ROS2_DOCKER_SECCOMP:-unconfined}" in
  default|"") ;;
  unconfined) security_args+=(--security-opt seccomp=unconfined) ;;
  *) security_args+=(--security-opt "seccomp=\${ROS2_DOCKER_SECCOMP}") ;;
esac

x11_args=()
xauth_tmp=""
xauth_container_path=/tmp/.ros2-docker.Xauthority
cleanup() {
  if [[ -n "\${xauth_tmp}" && -f "\${xauth_tmp}" ]]; then
    rm -f -- "\${xauth_tmp}"
  fi
}
trap cleanup EXIT

xauth_merge_nlist() {
  local source=$1
  local display_number=$2
  local query
  local -a queries=(
    "\${DISPLAY}"
    "localhost:\${display_number}"
    "127.0.0.1:\${display_number}"
    ":\${display_number}"
    "\$(hostname)/unix:\${display_number}"
  )

  for query in "\${queries[@]}"; do
    XAUTHORITY="\${source}" xauth nlist "\${query}" 2>/dev/null \
      | sed -e 's/^..../ffff/' \
      | xauth -f "\${xauth_tmp}" nmerge - 2>/dev/null || true
  done

  XAUTHORITY="\${source}" xauth list 2>/dev/null \
    | awk -v display_number="\${display_number}" '
        {
          split(\$1, parts, ":")
          split(parts[2], screen, ".")
          if (screen[1] == display_number) print \$1
        }
      ' \
    | while IFS= read -r entry; do
        XAUTHORITY="\${source}" xauth nlist "\${entry}" 2>/dev/null \
          | sed -e 's/^..../ffff/' \
          | xauth -f "\${xauth_tmp}" nmerge - 2>/dev/null || true
      done
}

xauth_merge_sudo_user() {
  local display_number=$1
  local query
  local -a queries=(
    "\${DISPLAY}"
    "localhost:\${display_number}"
    "127.0.0.1:\${display_number}"
    ":\${display_number}"
    "\$(hostname)/unix:\${display_number}"
  )

  for query in "\${queries[@]}"; do
    sudo -H -u "\${SUDO_USER}" xauth nlist "\${query}" 2>/dev/null \
      | sed -e 's/^..../ffff/' \
      | xauth -f "\${xauth_tmp}" nmerge - 2>/dev/null || true
  done

  sudo -H -u "\${SUDO_USER}" xauth list 2>/dev/null \
    | awk -v display_number="\${display_number}" '
        {
          split(\$1, parts, ":")
          split(parts[2], screen, ".")
          if (screen[1] == display_number) print \$1
        }
      ' \
    | while IFS= read -r entry; do
        sudo -H -u "\${SUDO_USER}" xauth nlist "\${entry}" 2>/dev/null \
          | sed -e 's/^..../ffff/' \
          | xauth -f "\${xauth_tmp}" nmerge - 2>/dev/null || true
      done
}

if [[ -n "\${DISPLAY:-}" ]]; then
  x11_args+=(-e "DISPLAY=\${DISPLAY}" -v /tmp/.X11-unix:/tmp/.X11-unix:rw)

  if command -v xauth >/dev/null 2>&1; then
    display_number="\${DISPLAY##*:}"
    display_number="\${display_number%%.*}"
    xauth_tmp=\$(mktemp -t ros2-docker-xauth.XXXXXX)
    touch "\${xauth_tmp}"
    chmod 0644 "\${xauth_tmp}"

    xauth_sources=()
    [[ -n "\${XAUTHORITY:-}" ]] && xauth_sources+=("\${XAUTHORITY}")
    [[ -n "\${caller_home}" ]] && xauth_sources+=("\${caller_home}/.Xauthority")
    [[ -n "\${HOME:-}" ]] && xauth_sources+=("\${HOME}/.Xauthority")

    for source in "\${xauth_sources[@]}"; do
      [[ -r "\${source}" ]] || continue
      xauth_merge_nlist "\${source}" "\${display_number}"
      [[ -s "\${xauth_tmp}" ]] && break
    done

    if [[ ! -s "\${xauth_tmp}" && \${EUID} -eq 0 && -n "\${SUDO_USER:-}" ]] && command -v sudo >/dev/null 2>&1; then
      xauth_merge_sudo_user "\${display_number}"
    fi
  fi

  if [[ -n "\${xauth_tmp}" && -s "\${xauth_tmp}" ]]; then
    chmod 0644 "\${xauth_tmp}"
    x11_args+=(-e "XAUTHORITY=\${xauth_container_path}" -v "\${xauth_tmp}:\${xauth_container_path}:ro")
  else
    [[ -n "\${xauth_tmp}" ]] && rm -f -- "\${xauth_tmp}"
    xauth_tmp=""
    host_xauth="\${XAUTHORITY:-}"
    if [[ -z "\${host_xauth}" && -n "\${caller_home}" ]]; then
      host_xauth="\${caller_home}/.Xauthority"
    fi
    if [[ -r "\${host_xauth}" ]]; then
      x11_args+=(-e "XAUTHORITY=\${xauth_container_path}" -v "\${host_xauth}:\${xauth_container_path}:ro")
    else
      echo "warning: DISPLAY=\${DISPLAY} but no readable Xauthority cookie was found; GUI apps may fail." >&2
    fi
  fi
else
  echo "warning: DISPLAY is not set; starting without X11 GUI forwarding." >&2
fi

exec docker run --rm "\${docker_tty[@]}" \
  --network=host \
  --ipc=host \
  --init \
  "\${security_args[@]}" \
  "\${env_args[@]}" \
  "\${x11_args[@]}" \
  "\${IMAGE}" "\$@"
RUNSCRIPT
chmod 0755 "${run_script}"

owner="${SUDO_UID:-$(id -u)}:${SUDO_GID:-$(id -g)}"
chown "${owner}" "${archive}" "${dockerfile}" "${run_script}"

echo "Wrote Docker artifacts:"
echo "  ${archive}"
echo "  ${dockerfile}"
echo "  ${run_script}"
echo "  zstd level: ${ZSTD_LEVEL} (override with ZSTD_LEVEL=3 for faster iteration)"
echo
echo "Import on another machine:"
echo "  zstd -dc ${archive_name} | docker import --change 'ENTRYPOINT [\"/usr/local/bin/ros2-docker-entrypoint.sh\"]' --change 'CMD [\"bash\"]' --change 'USER ros2' --change 'WORKDIR ${ROS_WORKSPACE}' --change 'ENV ROS_DISTRO=${ROS_DISTRO} ROS_VERSION=${ROS_VERSION} ROS_PYTHON_VERSION=${ROS_PYTHON_VERSION} LANG=C.UTF-8 LC_ALL=C.UTF-8' - ${image_name}"
echo
echo "Run with ROS-friendly defaults:"
echo "  docker run --rm -it --network=host --ipc=host --init ${image_name}"
echo "  ./${run_script_name}"