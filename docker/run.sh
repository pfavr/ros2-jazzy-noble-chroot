#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

usage() {
  cat <<USAGE
Usage: $0 [OPTIONS] [--] [COMMAND ...]

Options:
  --extensions       Use ros2-jazzy:extensions (default)
  --gui              Use ros2-jazzy:gui
  --source           Use ros2-jazzy:extensions-source
  --sourcebuilt      Use ros2-jazzy-noble:sourcebuilt
  --image IMAGE      Use an explicit image tag
  --container NAME   Use an explicit persistent container name
  --no-persist       Set ROS2_DOCKER_PERSIST=0 for this run
  -h, --help         Show this help

All remaining arguments are passed to the container command.
USAGE
}

image=${ROS2_DOCKER_IMAGE:-ros2-jazzy:extensions}
container=${ROS2_DOCKER_CONTAINER:-ros2-jazzy-extensions}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --extensions)
      image=${ROS2_DOCKER_EXTENSIONS_TAG:-ros2-jazzy:extensions}
      container=${ROS2_DOCKER_CONTAINER:-ros2-jazzy-extensions}
      shift
      ;;
    --gui)
      image=${ROS2_DOCKER_GUI_TAG:-ros2-jazzy:gui}
      container=${ROS2_DOCKER_CONTAINER:-ros2-jazzy-gui}
      shift
      ;;
    --source)
      image=${ROS2_DOCKER_EXTENSIONS_SOURCE_TAG:-ros2-jazzy:extensions-source}
      container=${ROS2_DOCKER_CONTAINER:-ros2-jazzy-extensions-source}
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
