#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
dockerfile="${repo_root}/docker/Dockerfile"

ROS2_DOCKER_UPSTREAM_IMAGE=${ROS2_DOCKER_UPSTREAM_IMAGE:-ros:jazzy-ros-base-noble}
ROS2_IMAGE_REPO=${ROS2_IMAGE_REPO:-robot/ros2}
ROS2_DOCKER_BASE_TAG=${ROS2_DOCKER_BASE_TAG:-ros2-jazzy:base}
ROS2_DOCKER_DEV_TAG=${ROS2_DOCKER_DEV_TAG:-ros2-jazzy:dev}
ROS2_DOCKER_RUNTIME_TAG=${ROS2_DOCKER_RUNTIME_TAG:-ros2-jazzy:runtime}
ROS2_DOCKER_GUI_TAG=${ROS2_DOCKER_GUI_TAG:-ros2-jazzy:gui}
ROS2_DOCKER_BAGTOOLS_TAG=${ROS2_DOCKER_BAGTOOLS_TAG:-ros2-jazzy:bagtools}
ROS2_DOCKER_JETSON_DEV_TAG=${ROS2_DOCKER_JETSON_DEV_TAG:-ros2-jazzy:jetson-dev}
ROS2_DOCKER_ROBOT_RUNTIME_TAG=${ROS2_DOCKER_ROBOT_RUNTIME_TAG:-ros2-jazzy:robot-runtime}
export BUILDX_GIT_INFO=${BUILDX_GIT_INFO:-0}

git_sha() {
  local sha=""
  if [[ -n "${SUDO_USER:-}" ]] && command -v sudo >/dev/null 2>&1; then
    sha=$(sudo -u "${SUDO_USER}" git -C "${repo_root}" rev-parse --short=12 HEAD 2>/dev/null || true)
  fi
  if [[ -z "${sha}" ]]; then
    sha=$(git -C "${repo_root}" rev-parse --short=12 HEAD 2>/dev/null || true)
  fi
  printf '%s\n' "${sha:-local}"
}

GIT_SHA=${GIT_SHA:-$(git_sha)}

usage() {
  cat <<USAGE
Usage: $0 TARGET [TARGET ...]

Targets:
  base                         Build ${ROS2_DOCKER_BASE_TAG}
  dev-amd64                    Build ${ROS2_DOCKER_DEV_TAG}
  runtime-amd64                Build ${ROS2_DOCKER_RUNTIME_TAG}
  gui-amd64                    Build ${ROS2_DOCKER_GUI_TAG}
  bagtools-amd64               Build ${ROS2_DOCKER_BAGTOOLS_TAG}
  jetson-dev-arm64             Build ${ROS2_DOCKER_JETSON_DEV_TAG}
  robot-runtime-arm64          Build ${ROS2_DOCKER_ROBOT_RUNTIME_TAG}
  multiarch-runtime            Build/push linux/amd64,linux/arm64 runtime image
  all                          Build base, dev, runtime, gui, and bagtools for amd64

Compatibility aliases:
  dev, runtime, gui, bagtools, extensions

Environment:
  ROS2_DOCKER_UPSTREAM_IMAGE   Default: ${ROS2_DOCKER_UPSTREAM_IMAGE}
  ROS2_IMAGE_REPO              Default: ${ROS2_IMAGE_REPO}
  GIT_SHA                      Default: ${GIT_SHA}
  ROS2_DOCKER_PUSH=1           Push images instead of loading them locally
  INSTALL_FIREFOX=1            Include Firefox in the gui image
  INSTALL_FOXGLOVE_DESKTOP=1   Include Foxglove Desktop in the gui image
  INSTALL_VSCODE=1             Include VS Code desktop in the gui image
  BUILDX_GIT_INFO=1            Re-enable Buildx git provenance metadata
USAGE
}

output_args=()
if [[ "${ROS2_DOCKER_PUSH:-0}" == "1" ]]; then
  output_args+=(--push)
else
  output_args+=(--load)
fi

common_args=(
  -f "${dockerfile}"
  --build-arg "ROS_BASE_IMAGE=${ROS2_DOCKER_UPSTREAM_IMAGE}"
)

build_target() {
  local target=$1
  local platform=$2
  shift 2

  docker buildx build "${output_args[@]}" \
    "${common_args[@]}" \
    --target "${target}" \
    --platform "${platform}" \
    "$@" \
    "${repo_root}"
}

build_base() {
  build_target base linux/amd64 \
    -t "${ROS2_DOCKER_BASE_TAG}" \
    -t "ros2-jazzy:extensions"
}

build_dev_amd64() {
  build_target dev linux/amd64 \
    -t "${ROS2_DOCKER_DEV_TAG}" \
    -t "${ROS2_IMAGE_REPO}:dev-amd64-${GIT_SHA}"
}

build_runtime_amd64() {
  build_target runtime linux/amd64 \
    -t "${ROS2_DOCKER_RUNTIME_TAG}" \
    -t "${ROS2_IMAGE_REPO}:runtime-amd64-${GIT_SHA}"
}

build_gui_amd64() {
  build_target gui linux/amd64 \
    --build-arg "INSTALL_FIREFOX=${INSTALL_FIREFOX:-0}" \
    --build-arg "INSTALL_FOXGLOVE_DESKTOP=${INSTALL_FOXGLOVE_DESKTOP:-0}" \
    --build-arg "INSTALL_VSCODE=${INSTALL_VSCODE:-0}" \
    --build-arg "FOXGLOVE_DEB_URL=${FOXGLOVE_DEB_URL:-}" \
    -t "${ROS2_DOCKER_GUI_TAG}" \
    -t "${ROS2_IMAGE_REPO}:gui-amd64-${GIT_SHA}"
}

build_bagtools_amd64() {
  build_target bagtools linux/amd64 \
    -t "${ROS2_DOCKER_BAGTOOLS_TAG}" \
    -t "${ROS2_IMAGE_REPO}:bagtools-amd64-${GIT_SHA}"
}

build_jetson_dev_arm64() {
  build_target jetson-dev linux/arm64 \
    -t "${ROS2_DOCKER_JETSON_DEV_TAG}" \
    -t "${ROS2_IMAGE_REPO}:jetson-dev-arm64-${GIT_SHA}"
}

build_robot_runtime_arm64() {
  build_target robot-runtime linux/arm64 \
    -t "${ROS2_DOCKER_ROBOT_RUNTIME_TAG}" \
    -t "${ROS2_IMAGE_REPO}:robot-runtime-arm64-${GIT_SHA}"
}

build_multiarch_runtime() {
  if [[ "${ROS2_DOCKER_PUSH:-0}" != "1" ]]; then
    echo "error: multiarch-runtime requires ROS2_DOCKER_PUSH=1 because Docker cannot --load multi-platform images." >&2
    exit 2
  fi
  build_target runtime linux/amd64,linux/arm64 \
    -t "${ROS2_IMAGE_REPO}:runtime-${GIT_SHA}"
}

if [[ $# -eq 0 ]]; then
  usage >&2
  exit 2
fi

for target in "$@"; do
  case "${target}" in
    base) build_base ;;
    dev|dev-amd64) build_dev_amd64 ;;
    extensions) build_base ;;
    runtime|runtime-amd64) build_runtime_amd64 ;;
    gui|gui-amd64) build_gui_amd64 ;;
    bagtools|bagtools-amd64) build_bagtools_amd64 ;;
    jetson-dev-arm64) build_jetson_dev_arm64 ;;
    robot-runtime-arm64) build_robot_runtime_arm64 ;;
    multiarch-runtime) build_multiarch_runtime ;;
    all)
      build_base
      build_dev_amd64
      build_runtime_amd64
      build_gui_amd64
      build_bagtools_amd64
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      usage >&2
      echo "error: unknown build target: ${target}" >&2
      exit 2
      ;;
  esac
done
