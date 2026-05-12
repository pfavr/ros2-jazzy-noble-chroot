#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

keep_artifacts=0
if [[ "${1:-}" == "--keep-artifacts" ]]; then
  keep_artifacts=1
  shift
fi

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Usage: $0 [--keep-artifacts]"
  exit 0
fi

if [[ $# -ne 0 ]]; then
  echo "Usage: $0 [--keep-artifacts]" >&2
  exit 2
fi

cd "${SCRIPT_DIR}"

if [[ ${keep_artifacts} -eq 1 ]]; then
  ./scripts/clean-rootfs.sh
else
  ./scripts/clean-rootfs.sh --artifacts
fi

echo "Cleaned generated files."