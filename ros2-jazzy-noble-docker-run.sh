#!/usr/bin/env bash
set -euo pipefail

IMAGE="${ROS2_DOCKER_IMAGE:-ros2-jazzy-noble:sourcebuilt}"
CONTAINER="${ROS2_DOCKER_CONTAINER:-ros2-jazzy-noble-sourcebuilt}"

case "${ROS2_DOCKER_PERSIST:-1}" in
  1|true|yes|on) persistent=1 ;;
  0|false|no|off) persistent=0 ;;
  *) echo "error: ROS2_DOCKER_PERSIST must be 1/0, true/false, yes/no, or on/off." >&2; exit 2 ;;
esac

caller_home="${HOME:-}"
caller_uid=$(id -u)
caller_gid=$(id -g)
if [[ ${EUID} -eq 0 && -n "${SUDO_USER:-}" ]]; then
  caller_home=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
  caller_uid=${SUDO_UID:-$(id -u "${SUDO_USER}")}
  caller_gid=${SUDO_GID:-$(id -g "${SUDO_USER}")}
fi

docker_tty=()
if [[ -t 0 && -t 1 ]]; then
  docker_tty=(-it)
else
  docker_tty=(-i)
fi

env_args=()
for name in ROS_DOMAIN_ID RMW_IMPLEMENTATION; do
  if [[ -n "${!name:-}" ]]; then
    env_args+=(-e "${name}=${!name}")
  fi
done

security_args=()
case "${ROS2_DOCKER_SECCOMP:-unconfined}" in
  default|"") ;;
  unconfined) security_args+=(--security-opt seccomp=unconfined) ;;
  *) security_args+=(--security-opt "seccomp=${ROS2_DOCKER_SECCOMP}") ;;
esac

x11_args=()
x11_exec_args=()
xauth_tmp=""
xauth_cleanup=0
xauth_container_path=/tmp/.ros2-docker.Xauthority
cleanup() {
  if (( xauth_cleanup == 1 )) && [[ -n "${xauth_tmp}" && -f "${xauth_tmp}" ]]; then
    rm -f -- "${xauth_tmp}"
  fi
}
trap cleanup EXIT

xauth_merge_nlist() {
  local source=$1
  local display_number=$2
  local query
  local -a queries=(
    "${DISPLAY}"
    "localhost:${display_number}"
    "127.0.0.1:${display_number}"
    ":${display_number}"
    "$(hostname)/unix:${display_number}"
  )

  for query in "${queries[@]}"; do
    XAUTHORITY="${source}" xauth nlist "${query}" 2>/dev/null \
      | sed -e 's/^..../ffff/' \
      | xauth -f "${xauth_tmp}" nmerge - 2>/dev/null || true
  done

  XAUTHORITY="${source}" xauth list 2>/dev/null \
    | awk -v display_number="${display_number}" '
        {
          split($1, parts, ":")
          split(parts[2], screen, ".")
          if (screen[1] == display_number) print $1
        }
      ' \
    | while IFS= read -r entry; do
        XAUTHORITY="${source}" xauth nlist "${entry}" 2>/dev/null \
          | sed -e 's/^..../ffff/' \
          | xauth -f "${xauth_tmp}" nmerge - 2>/dev/null || true
      done
}

xauth_merge_sudo_user() {
  local display_number=$1
  local query
  local -a queries=(
    "${DISPLAY}"
    "localhost:${display_number}"
    "127.0.0.1:${display_number}"
    ":${display_number}"
    "$(hostname)/unix:${display_number}"
  )

  for query in "${queries[@]}"; do
    sudo -H -u "${SUDO_USER}" xauth nlist "${query}" 2>/dev/null \
      | sed -e 's/^..../ffff/' \
      | xauth -f "${xauth_tmp}" nmerge - 2>/dev/null || true
  done

  sudo -H -u "${SUDO_USER}" xauth list 2>/dev/null \
    | awk -v display_number="${display_number}" '
        {
          split($1, parts, ":")
          split(parts[2], screen, ".")
          if (screen[1] == display_number) print $1
        }
      ' \
    | while IFS= read -r entry; do
        sudo -H -u "${SUDO_USER}" xauth nlist "${entry}" 2>/dev/null \
          | sed -e 's/^..../ffff/' \
          | xauth -f "${xauth_tmp}" nmerge - 2>/dev/null || true
      done
}

if [[ -n "${DISPLAY:-}" ]]; then
  x11_args+=(-e "DISPLAY=${DISPLAY}" -v /tmp/.X11-unix:/tmp/.X11-unix:rw)
  x11_exec_args+=(-e "DISPLAY=${DISPLAY}")

  if command -v xauth >/dev/null 2>&1; then
    display_number="${DISPLAY##*:}"
    display_number="${display_number%%.*}"
    if (( persistent == 1 )); then
      xauth_state_dir="${ROS2_DOCKER_STATE_DIR:-/tmp/ros2-docker-${caller_uid}}"
      mkdir -p "${xauth_state_dir}"
      chmod 0700 "${xauth_state_dir}" 2>/dev/null || true
      if [[ ${EUID} -eq 0 && -n "${SUDO_UID:-}" ]]; then
        chown "${caller_uid}:${caller_gid}" "${xauth_state_dir}" 2>/dev/null || true
      fi
      xauth_tmp="${xauth_state_dir}/${CONTAINER}.Xauthority"
      : >"${xauth_tmp}"
    else
      xauth_tmp=$(mktemp -t ros2-docker-xauth.XXXXXX)
      xauth_cleanup=1
    fi
    chmod 0644 "${xauth_tmp}"

    xauth_sources=()
    [[ -n "${XAUTHORITY:-}" ]] && xauth_sources+=("${XAUTHORITY}")
    [[ -n "${caller_home}" ]] && xauth_sources+=("${caller_home}/.Xauthority")
    [[ -n "${HOME:-}" ]] && xauth_sources+=("${HOME}/.Xauthority")

    for source in "${xauth_sources[@]}"; do
      [[ -r "${source}" ]] || continue
      xauth_merge_nlist "${source}" "${display_number}"
      [[ -s "${xauth_tmp}" ]] && break
    done

    if [[ ! -s "${xauth_tmp}" && ${EUID} -eq 0 && -n "${SUDO_USER:-}" ]] && command -v sudo >/dev/null 2>&1; then
      xauth_merge_sudo_user "${display_number}"
    fi
  fi

  if [[ -n "${xauth_tmp}" && -s "${xauth_tmp}" ]]; then
    chmod 0644 "${xauth_tmp}"
    x11_args+=(-e "XAUTHORITY=${xauth_container_path}" -v "${xauth_tmp}:${xauth_container_path}:ro")
    x11_exec_args+=(-e "XAUTHORITY=${xauth_container_path}")
  else
    host_xauth="${XAUTHORITY:-}"
    if [[ -z "${host_xauth}" && -n "${caller_home}" ]]; then
      host_xauth="${caller_home}/.Xauthority"
    fi
    if [[ -r "${host_xauth}" ]]; then
      if (( persistent == 1 && -n "${xauth_tmp}" )); then
        cp "${host_xauth}" "${xauth_tmp}" 2>/dev/null || true
      fi
      if [[ -n "${xauth_tmp}" && -s "${xauth_tmp}" ]]; then
        chmod 0644 "${xauth_tmp}"
        x11_args+=(-e "XAUTHORITY=${xauth_container_path}" -v "${xauth_tmp}:${xauth_container_path}:ro")
      else
        [[ -n "${xauth_tmp}" && ${xauth_cleanup} -eq 1 ]] && rm -f -- "${xauth_tmp}"
        xauth_tmp=""
        x11_args+=(-e "XAUTHORITY=${xauth_container_path}" -v "${host_xauth}:${xauth_container_path}:ro")
      fi
      x11_exec_args+=(-e "XAUTHORITY=${xauth_container_path}")
    else
      echo "warning: DISPLAY=${DISPLAY} but no readable Xauthority cookie was found; GUI apps may fail." >&2
    fi
  fi
else
  echo "warning: DISPLAY is not set; starting without X11 GUI forwarding." >&2
fi

gpu_args=()
if [[ -d /dev/dri ]]; then
  gpu_args+=(--device /dev/dri:/dev/dri)

  if getent group render >/dev/null; then
    gpu_args+=(--group-add "$(getent group render | cut -d: -f3)")
  fi

  if getent group video >/dev/null; then
    gpu_args+=(--group-add "$(getent group video | cut -d: -f3)")
  fi
fi

if (( persistent == 1 )); then
  if docker container inspect "${CONTAINER}" >/dev/null 2>&1; then
    if [[ "$(docker inspect -f '{{.State.Running}}' "${CONTAINER}")" != "true" ]]; then
      docker start "${CONTAINER}" >/dev/null
    fi
  else
    docker run -d --name "${CONTAINER}" \
      --network=host \
      --ipc=host \
      --init \
      "${security_args[@]}" \
      "${env_args[@]}" \
      "${x11_args[@]}" \
      "${gpu_args[@]}" \
      "${IMAGE}" tail -f /dev/null >/dev/null
  fi

  if [[ "$(docker inspect -f '{{.State.Running}}' "${CONTAINER}")" != "true" ]]; then
    echo "error: persistent container ${CONTAINER} is not running. Remove it with: docker rm ${CONTAINER}" >&2
    exit 1
  fi

  exec docker exec "${docker_tty[@]}" \
    "${env_args[@]}" \
    "${x11_exec_args[@]}" \
    "${CONTAINER}" /usr/local/bin/ros2-docker-entrypoint.sh "$@"
fi

exec docker run --rm "${docker_tty[@]}" \
  --network=host \
  --ipc=host \
  --init \
  "${security_args[@]}" \
  "${env_args[@]}" \
  "${x11_args[@]}" \
  "${gpu_args[@]}" \
  "${IMAGE}" "$@"
