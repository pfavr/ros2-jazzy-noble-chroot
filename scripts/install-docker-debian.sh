#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: sudo $0 [options]

Install Docker Engine from Docker's official Debian apt repository.

Targets Debian Trixie. On Debian sid/unstable/testing snapshots, the script
uses Docker's trixie repository by default because Docker normally publishes
repositories for released Debian codenames, not sid.

Options:
  --codename NAME   Use a specific Docker Debian repository codename.
                    Can also be set with DOCKER_DEBIAN_CODENAME.
  --no-add-user     Do not add the invoking user to the docker group.
  --test            Run 'docker run --rm hello-world' after installation.
  -h, --help        Show this help.

Environment:
  DOCKER_DEBIAN_CODENAME  Override the repository codename, e.g. trixie.
  DOCKER_USER             User to add to the docker group. Defaults to SUDO_USER.
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

need_root() {
  if [[ ${EUID} -ne 0 ]]; then
    exec sudo -E "$0" "$@"
  fi
}

repo_codename_override=${DOCKER_DEBIAN_CODENAME:-}
add_invoking_user=1
run_hello_world=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --codename)
      [[ $# -ge 2 ]] || die "--codename requires an argument."
      repo_codename_override=$2
      shift 2
      ;;
    --no-add-user)
      add_invoking_user=0
      shift
      ;;
    --test)
      run_hello_world=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

need_root "$@"

[[ -r /etc/os-release ]] || die "Cannot read /etc/os-release."
# shellcheck disable=SC1091
source /etc/os-release

if [[ ${ID:-} != debian ]]; then
  die "This installer is intended for Debian hosts only (detected ID=${ID:-unknown})."
fi

detected_codename=${VERSION_CODENAME:-}
if [[ -z ${detected_codename} && -r /etc/debian_version ]]; then
  detected_codename=$(cut -d/ -f1 /etc/debian_version | tr -d '[:space:]')
fi

repo_codename=${repo_codename_override:-${detected_codename}}
case "${repo_codename}" in
  sid|unstable|testing|forky|forky/sid|trixie/sid)
    echo "Detected Debian ${repo_codename}; using Docker's trixie apt repository."
    echo "Override with --codename or DOCKER_DEBIAN_CODENAME if Docker publishes a better match."
    repo_codename=trixie
    ;;
  "")
    echo "Could not determine Debian codename; using Docker's trixie apt repository."
    repo_codename=trixie
    ;;
esac

architecture=$(dpkg --print-architecture)
export DEBIAN_FRONTEND=noninteractive

echo "Installing Docker Engine for Debian repository codename: ${repo_codename}"
echo "Architecture: ${architecture}"

apt-get update
apt-get install -y ca-certificates curl gnupg

conflicting_packages=(
  docker.io
  docker-doc
  docker-compose
  docker-compose-v2
  podman-docker
  containerd
  runc
)

installed_conflicts=()
for package_name in "${conflicting_packages[@]}"; do
  if dpkg-query -W -f='${Status}' "${package_name}" 2>/dev/null | grep -q '^install ok installed$'; then
    installed_conflicts+=("${package_name}")
  fi
done

if (( ${#installed_conflicts[@]} > 0 )); then
  echo "Removing conflicting distro packages: ${installed_conflicts[*]}"
  apt-get remove -y "${installed_conflicts[@]}"
fi

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

cat > /etc/apt/sources.list.d/docker.list <<APT_SOURCE
deb [arch=${architecture} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${repo_codename} stable
APT_SOURCE

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
  systemctl enable --now docker
else
  service docker start >/dev/null 2>&1 || true
fi

target_user=${DOCKER_USER:-${SUDO_USER:-}}
if [[ ${add_invoking_user} -eq 1 && -n ${target_user} && ${target_user} != root ]]; then
  if getent passwd "${target_user}" >/dev/null; then
    usermod -aG docker "${target_user}"
    echo "Added ${target_user} to the docker group. Log out and back in, or run 'newgrp docker', before using docker without sudo."
  else
    echo "warning: DOCKER_USER/SUDO_USER '${target_user}' does not exist; not adding a user to the docker group." >&2
  fi
fi

docker --version
docker compose version

if [[ ${run_hello_world} -eq 1 ]]; then
  docker run --rm hello-world
else
  echo "To verify Docker, run: sudo docker run --rm hello-world"
fi

echo "Docker installation finished."