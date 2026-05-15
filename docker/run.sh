#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

usage() {
  cat <<USAGE
Usage: $0 [OPTIONS] [--] [COMMAND ...]

Options:
  --dev              Use ros2-jazzy:dev (default)
  --base             Use ros2-jazzy:base
  --runtime          Use ros2-jazzy:runtime
  --gui              Use ros2-jazzy:gui
  --bagtools         Use ros2-jazzy:bagtools
  --jetson-dev       Use ros2-jazzy:jetson-dev
  --robot-runtime    Use ros2-jazzy:robot-runtime
  --extensions       Compatibility alias for --base
  --sourcebuilt      Use ros2-jazzy-noble:sourcebuilt
  --image IMAGE      Use an explicit image tag
  --container NAME   Use an explicit persistent container name
  --no-persist       Set ROS2_DOCKER_PERSIST=0 for this run
  -h, --help         Show this help

All remaining arguments are passed to the container command.
USAGE
}

image=${ROS2_DOCKER_IMAGE:-ros2-jazzy:dev}
container=${ROS2_DOCKER_CONTAINER:-ros2-jazzy-dev}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dev)
      image=${ROS2_DOCKER_DEV_TAG:-ros2-jazzy:dev}
      container=${ROS2_DOCKER_CONTAINER:-ros2-jazzy-dev}
      shift
      ;;
    --base|--extensions)
      image=${ROS2_DOCKER_BASE_TAG:-ros2-jazzy:base}
      container=${ROS2_DOCKER_CONTAINER:-ros2-jazzy-base}
      shift
      ;;
    --runtime)
      image=${ROS2_DOCKER_RUNTIME_TAG:-ros2-jazzy:runtime}
      container=${ROS2_DOCKER_CONTAINER:-ros2-jazzy-runtime}
      shift
      ;;
    --gui)
      image=${ROS2_DOCKER_GUI_TAG:-ros2-jazzy:gui}
      container=${ROS2_DOCKER_CONTAINER:-ros2-jazzy-gui}
      shift
      ;;
    --bagtools)
      image=${ROS2_DOCKER_BAGTOOLS_TAG:-ros2-jazzy:bagtools}
      container=${ROS2_DOCKER_CONTAINER:-ros2-jazzy-bagtools}
      shift
      ;;
    --jetson-dev)
      image=${ROS2_DOCKER_JETSON_DEV_TAG:-ros2-jazzy:jetson-dev}
      container=${ROS2_DOCKER_CONTAINER:-ros2-jazzy-jetson-dev}
      shift
      ;;
    --robot-runtime)
      image=${ROS2_DOCKER_ROBOT_RUNTIME_TAG:-ros2-jazzy:robot-runtime}
      container=${ROS2_DOCKER_CONTAINER:-ros2-jazzy-robot-runtime}
      shift
      ;;
    --sourcebuilt)
      image=${ROS2_DOCKER_SOURCEBUILT_TAG:-ros2-jazzy-noble:sourcebuilt}
      container=${ROS2_DOCKER_CONTAINER:-ros2-jazzy-noble-sourcebuilt}
      shift
      ;;
    --image)
      [[ $# -ge 2 ]] || { echo "error: --image requires a value" >&2; exit 2; }
      image=$2
      shift 2
      ;;
    --container)
      [[ $# -ge 2 ]] || { echo "error: --container requires a value" >&2; exit 2; }
      container=$2
      shift 2
      ;;
    --no-persist)
      export ROS2_DOCKER_PERSIST=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

export ROS2_DOCKER_IMAGE=${image}
export ROS2_DOCKER_CONTAINER=${container}

exec "${repo_root}/ros2-jazzy-noble-docker-run.sh" "$@"
