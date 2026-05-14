#!/usr/bin/env bash
set -euo pipefail

IMAGE="${ROS2_DOCKER_IMAGE:-ros2-jazzy-noble:sourcebuilt}"

caller_home="${HOME:-}"
if [[ ${EUID} -eq 0 && -n "${SUDO_USER:-}" ]]; then
  caller_home=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
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
xauth_tmp=""
xauth_container_path=/tmp/.ros2-docker.Xauthority
cleanup() {
  if [[ -n "${xauth_tmp}" && -f "${xauth_tmp}" ]]; then
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

  if command -v xauth >/dev/null 2>&1; then
    display_number="${DISPLAY##*:}"
    display_number="${display_number%%.*}"
    xauth_tmp=$(mktemp -t ros2-docker-xauth.XXXXXX)
    touch "${xauth_tmp}"
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
  else
    [[ -n "${xauth_tmp}" ]] && rm -f -- "${xauth_tmp}"
    xauth_tmp=""
    host_xauth="${XAUTHORITY:-}"
    if [[ -z "${host_xauth}" && -n "${caller_home}" ]]; then
      host_xauth="${caller_home}/.Xauthority"
    fi
    if [[ -r "${host_xauth}" ]]; then
      x11_args+=(-e "XAUTHORITY=${xauth_container_path}" -v "${host_xauth}:${xauth_container_path}:ro")
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

exec docker run --rm "${docker_tty[@]}" \
  --network=host \
  --ipc=host \
  --init \
  "${security_args[@]}" \
  "${env_args[@]}" \
  "${x11_args[@]}" \
  "${gpu_args[@]}" \
  "${IMAGE}" "$@"
