#!/usr/bin/env bash
set -euo pipefail

IMAGE=${ROS2_DOCKER_IMAGE:-ros2-jazzy:base}

docker run --rm --network=host --ipc=host --init "${IMAGE}" bash -lc '
set -euo pipefail

ros2 --help >/dev/null
ros2 pkg prefix foxglove_bridge >/dev/null
ros2 pkg prefix xacro >/dev/null
ros2 pkg prefix rosx_introspection >/dev/null
ros2 pkg executables foxglove_bridge | grep -q "foxglove_bridge foxglove_bridge"
ros2 pkg executables demo_nodes_cpp | grep -q "demo_nodes_cpp talker"

timeout --preserve-status 3 ros2 run demo_nodes_cpp talker >/dev/null 2>&1 || {
  rc=$?
  [[ ${rc} -eq 124 || ${rc} -eq 143 ]]
}
'

echo "Docker image smoke test passed: ${IMAGE}"
