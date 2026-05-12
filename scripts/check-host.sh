#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

missing=0

check_command() {
  local command_name=$1
  local package_name=$2

  if command -v "${command_name}" >/dev/null 2>&1; then
    printf 'ok: %s\n' "${command_name}"
  else
    printf 'missing: %s (install package: %s)\n' "${command_name}" "${package_name}"
    missing=1
  fi
}

check_path() {
  local command_path=$1
  local package_name=$2

  if [[ -x "${command_path}" ]]; then
    printf 'ok: %s\n' "${command_path}"
  else
    printf 'missing: %s (install package: %s)\n' "${command_path}" "${package_name}"
    missing=1
  fi
}

architecture=$(dpkg --print-architecture 2>/dev/null || uname -m)
if [[ "${architecture}" == "amd64" || "${architecture}" == "x86_64" ]]; then
  printf 'ok: architecture %s\n' "${architecture}"
else
  printf 'unsupported: architecture %s; this workflow targets amd64/x86_64\n' "${architecture}"
  missing=1
fi

check_command sudo sudo
check_path /usr/sbin/chroot coreutils
check_path "${DEBOOTSTRAP}" debootstrap
check_command mount mount
check_command tar tar

if command -v zstd >/dev/null 2>&1; then
  printf 'ok: zstd\n'
else
  printf 'optional: zstd is needed only for scripts/pack-rootfs.sh (install package: zstd)\n'
fi

exit "${missing}"
