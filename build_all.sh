#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

create_artifact=0
if [[ "${1:-}" == "--artifacts" ]]; then
  create_artifact=1
  shift
fi

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Usage: $0 [--artifacts]"
  exit 0
fi

if [[ $# -ne 0 ]]; then
  echo "Usage: $0 [--artifacts]" >&2
  exit 2
fi

cd "${SCRIPT_DIR}"

run_step() {
  local name=$1
  shift

  echo "==> ${name}"
  "$@" 2>&1 | tee "${name}.log"
}

run_step check-host ./scripts/check-host.sh
run_step create-rootfs ./scripts/create-rootfs.sh
run_step provision-rootfs ./scripts/provision-rootfs.sh
run_step fetch-sources ./scripts/fetch-sources.sh
run_step build-host ./scripts/build-ros2.sh
run_step smoke-test ./scripts/smoke-test.sh

if [[ ${create_artifact} -eq 1 ]]; then
  run_step pack-rootfs ./scripts/pack-rootfs.sh
fi

echo "Done."
if [[ ${create_artifact} -eq 1 ]]; then
  echo "Packed rootfs archive written under artifacts/."
fi