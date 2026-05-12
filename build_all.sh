#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# Default: build for redistribution (merge-install layout + pack a tarball).
# --no-artifacts switches to the historical dev workflow: --symlink-install
# layout (fast iteration, build/ NOT removable) and no packing.
create_artifact=1
build_mode=release

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-artifacts)
      create_artifact=0
      build_mode=dev
      shift
      ;;
    --artifacts)
      # Back-compat alias for the (now default) release flow.
      create_artifact=1
      build_mode=release
      shift
      ;;
    -h|--help)
      cat <<USAGE
Usage: $0 [--no-artifacts]

Without flags (default):
  Build ROS 2 with --merge-install so opt/ros2_ws/build is removable,
  then pack a redistributable tarball under artifacts/.

--no-artifacts:
  Build ROS 2 with --symlink-install (dev layout, fast incremental
  iteration; build/ is NOT removable). Skip packing the tarball.
USAGE
      exit 0
      ;;
    *)
      echo "Usage: $0 [--no-artifacts]" >&2
      exit 2
      ;;
  esac
done

cd "${SCRIPT_DIR}"

LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"

run_step() {
  local name=$1
  shift

  echo "==> ${name}"
  "$@" 2>&1 | tee "${LOG_DIR}/${name}.log"
  local status=${PIPESTATUS[0]}
  if [[ ${status} -ne 0 ]]; then
    echo "==> ${name} failed (exit ${status}); see ${LOG_DIR}/${name}.log" >&2
    return "${status}"
  fi
}

export BUILD_MODE="${build_mode}"

run_step check-host ./scripts/check-host.sh
run_step create-rootfs ./scripts/create-rootfs.sh
run_step provision-rootfs ./scripts/provision-rootfs.sh
run_step fetch-sources ./scripts/fetch-sources.sh
run_step build-ros2 ./scripts/build-ros2.sh
run_step smoke-test ./scripts/smoke-test.sh

if [[ ${create_artifact} -eq 1 ]]; then
  run_step pack-rootfs ./scripts/pack-rootfs.sh
fi

echo "Done (BUILD_MODE=${build_mode})."
if [[ ${create_artifact} -eq 1 ]]; then
  echo "Packed rootfs archive written under artifacts/."
fi
