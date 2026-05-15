#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

ROS2_DOCKER_UPSTREAM_IMAGE=${ROS2_DOCKER_UPSTREAM_IMAGE:-ros:jazzy-ros-base-noble}
ROS2_DOCKER_BASE_TAG=${ROS2_DOCKER_BASE_TAG:-ros2-jazzy:base}
ROS2_DOCKER_EXTENSIONS_TAG=${ROS2_DOCKER_EXTENSIONS_TAG:-ros2-jazzy:extensions}
ROS2_DOCKER_EXTENSIONS_SOURCE_TAG=${ROS2_DOCKER_EXTENSIONS_SOURCE_TAG:-ros2-jazzy:extensions-source}
ROS2_DOCKER_GUI_TAG=${ROS2_DOCKER_GUI_TAG:-ros2-jazzy:gui}
ROS2_DOCKER_APP_TAG=${ROS2_DOCKER_APP_TAG:-ros2-jazzy:app}
ROS2_DOCKER_APP_BASE_TAG=${ROS2_DOCKER_APP_BASE_TAG:-${ROS2_DOCKER_EXTENSIONS_TAG}}
export BUILDX_GIT_INFO=${BUILDX_GIT_INFO:-0}

usage() {
  cat <<USAGE
Usage: $0 TARGET [TARGET ...]

Targets:
  base               Build ${ROS2_DOCKER_BASE_TAG}
  extensions         Build ${ROS2_DOCKER_EXTENSIONS_TAG} from apt packages
  extensions-source  Build ${ROS2_DOCKER_EXTENSIONS_SOURCE_TAG} from ros2-extra.repos overlay
  gui                Build ${ROS2_DOCKER_GUI_TAG}
  app                Build ${ROS2_DOCKER_APP_TAG}; requires APP_SRC=/path/to/app_ws/src
  all                Build base, extensions, and gui

Environment:
  ROS2_DOCKER_UPSTREAM_IMAGE       Default: ${ROS2_DOCKER_UPSTREAM_IMAGE}
  ROS2_DOCKER_BASE_TAG             Default: ${ROS2_DOCKER_BASE_TAG}
  ROS2_DOCKER_EXTENSIONS_TAG       Default: ${ROS2_DOCKER_EXTENSIONS_TAG}
  ROS2_DOCKER_EXTENSIONS_SOURCE_TAG Default: ${ROS2_DOCKER_EXTENSIONS_SOURCE_TAG}
  ROS2_DOCKER_GUI_TAG              Default: ${ROS2_DOCKER_GUI_TAG}
  ROS2_DOCKER_APP_TAG              Default: ${ROS2_DOCKER_APP_TAG}
  APP_SRC                          Application workspace src directory for app target
  ROS2_DOCKER_PUSH=1               Push images instead of loading them locally
  INSTALL_FIREFOX=1                Include Firefox in the gui image
  INSTALL_FOXGLOVE_DESKTOP=1       Include Foxglove Desktop in the gui image
  INSTALL_VSCODE=1                 Include VS Code desktop in the gui image
  BUILDX_GIT_INFO=1                Re-enable Buildx git provenance metadata
USAGE
}

build_output_args=()
if [[ "${ROS2_DOCKER_PUSH:-0}" == "1" ]]; then
  build_output_args+=(--push)
else
  build_output_args+=(--load)
fi

build_base() {
  docker buildx build "${build_output_args[@]}" \
    -f "${repo_root}/docker/base.Dockerfile" \
    --build-arg "ROS_BASE_IMAGE=${ROS2_DOCKER_UPSTREAM_IMAGE}" \
    -t "${ROS2_DOCKER_BASE_TAG}" \
    "${repo_root}"
}

build_extensions() {
  docker buildx build "${build_output_args[@]}" \
    -f "${repo_root}/docker/extensions.Dockerfile" \
    --target apt \
    --build-arg "BASE_IMAGE=${ROS2_DOCKER_BASE_TAG}" \
    -t "${ROS2_DOCKER_EXTENSIONS_TAG}" \
    "${repo_root}"
}

build_extensions_source() {
  docker buildx build "${build_output_args[@]}" \
    -f "${repo_root}/docker/extensions.Dockerfile" \
    --target source \
    --build-arg "BASE_IMAGE=${ROS2_DOCKER_BASE_TAG}" \
    -t "${ROS2_DOCKER_EXTENSIONS_SOURCE_TAG}" \
    "${repo_root}"
}

build_gui() {
  docker buildx build "${build_output_args[@]}" \
    -f "${repo_root}/docker/gui.Dockerfile" \
    --build-arg "BASE_IMAGE=${ROS2_DOCKER_EXTENSIONS_TAG}" \
    --build-arg "INSTALL_FIREFOX=${INSTALL_FIREFOX:-0}" \
    --build-arg "INSTALL_FOXGLOVE_DESKTOP=${INSTALL_FOXGLOVE_DESKTOP:-0}" \
    --build-arg "INSTALL_VSCODE=${INSTALL_VSCODE:-0}" \
    --build-arg "FOXGLOVE_DEB_URL=${FOXGLOVE_DEB_URL:-}" \
    -t "${ROS2_DOCKER_GUI_TAG}" \
    "${repo_root}"
}

build_app() {
  if [[ -z "${APP_SRC:-}" ]]; then
    echo "error: APP_SRC must point to an application workspace src directory for the app target." >&2
    exit 2
  fi
  if [[ ! -d "${APP_SRC}" ]]; then
    echo "error: APP_SRC does not exist or is not a directory: ${APP_SRC}" >&2
    exit 2
  fi

  docker buildx build "${build_output_args[@]}" \
    -f "${repo_root}/docker/app.Dockerfile" \
    --build-context "app_src=${APP_SRC}" \
    --build-arg "EXTENSIONS_IMAGE=${ROS2_DOCKER_APP_BASE_TAG}" \
    --build-arg "RUNTIME_IMAGE=${ROS2_DOCKER_APP_BASE_TAG}" \
    -t "${ROS2_DOCKER_APP_TAG}" \
    "${repo_root}"
}

if [[ $# -eq 0 ]]; then
  usage >&2
  exit 2
fi

for target in "$@"; do
  case "${target}" in
    base) build_base ;;
    extensions) build_extensions ;;
    extensions-source) build_extensions_source ;;
    gui) build_gui ;;
    app) build_app ;;
    all)
      build_base
      build_extensions
      build_gui
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
