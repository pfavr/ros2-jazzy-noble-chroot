#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME=$(basename -- "$0")
ROS_WORKSPACE=${ROS_WORKSPACE:-/opt/ros2_ws}
LOG_DIR=/var/lib/ros2_config
LOG_FILE=${LOG_DIR}/history.log
VSCODE_SOURCE=/etc/apt/sources.list.d/vscode.sources
VSCODE_KEYRING=/usr/share/keyrings/microsoft.gpg
VSCODE_KEY_URL=https://packages.microsoft.com/keys/microsoft.asc
VSCODE_REPO_URL=https://packages.microsoft.com/repos/code
MOZILLA_SOURCE=/etc/apt/sources.list.d/mozilla.sources
MOZILLA_PREFERENCES=/etc/apt/preferences.d/mozilla
MOZILLA_KEYRING=/etc/apt/keyrings/packages.mozilla.org.asc
MOZILLA_KEY_URL=https://packages.mozilla.org/apt/repo-signing-key.gpg
MOZILLA_REPO_URL=https://packages.mozilla.org/apt

usage() {
  cat <<USAGE
Usage: ${SCRIPT_NAME} [--yes] [command]

Manage optional desktop tools inside this ROS 2 chroot.

Commands:
  status                 Show optional tool installation status.
  install vscode         Install Visual Studio Code desktop.
  remove vscode          Remove Visual Studio Code desktop.
  install foxglove       Install Foxglove Desktop.
  remove foxglove        Remove Foxglove Desktop.
  install firefox        Install Firefox from Mozilla's apt repo, not snap.
  remove firefox         Remove Firefox and Mozilla apt repo files.
  upgrade                Upgrade installed optional tools.
  menu                   Open the interactive menu (default).
  help                   Show this help.

Environment:
  FOXGLOVE_DEB_URL       Override the Foxglove Desktop .deb URL.
  ROS2_CONFIG_ALLOW_HOST Set to 1 to skip the chroot environment guard.
USAGE
}

say() {
  printf '%s\n' "$*"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo -n "$@"
  fi
}

ensure_sudo() {
  if (( EUID == 0 )); then
    return 0
  fi
  command -v sudo >/dev/null 2>&1 || die "sudo is required for install/remove actions."
  sudo -n true 2>/dev/null || die "Passwordless sudo is required inside this chroot."
}

ensure_chroot() {
  if [[ "${ROS2_CONFIG_ALLOW_HOST:-}" == "1" ]]; then
    return 0
  fi
  [[ -d "${ROS_WORKSPACE}" ]] || die "${SCRIPT_NAME} is intended to run inside the ROS 2 chroot; ${ROS_WORKSPACE} was not found."
}

log_action() {
  local message=$1
  local line
  line="$(date -Is) ${message}"
  if as_root mkdir -p "${LOG_DIR}" 2>/dev/null; then
    printf '%s\n' "${line}" | as_root tee -a "${LOG_FILE}" >/dev/null || true
  fi
}

package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q '^install ok installed$'
}

package_version() {
  dpkg-query -W -f='${Version}' "$1" 2>/dev/null || true
}

status_text() {
  local code_status=not-installed
  local foxglove_status=not-installed
  local firefox_status=not-installed

  if package_installed code; then
    code_status="installed ($(package_version code))"
  fi
  if package_installed foxglove-studio; then
    foxglove_status="installed ($(package_version foxglove-studio))"
  fi
  if package_installed firefox; then
    firefox_status="installed ($(package_version firefox))"
  fi

  cat <<STATUS
Optional tool status:
  VS Code:           ${code_status}
  Foxglove Desktop: ${foxglove_status}
  Firefox:           ${firefox_status}
STATUS
}

show_status() {
  status_text
}

confirm() {
  local prompt=$1
  if [[ "${ASSUME_YES:-0}" == "1" || ! -t 0 ]]; then
    return 0
  fi
  local answer
  read -r -p "${prompt} [y/N] " answer
  [[ "${answer}" == "y" || "${answer}" == "Y" || "${answer}" == "yes" || "${answer}" == "YES" ]]
}

warn_display() {
  if [[ -z "${DISPLAY:-}" ]]; then
    say "warning: DISPLAY is not set. Installation can continue, but GUI launch will need X11 forwarding or a local display."
  fi
}

apt_update() {
  as_root env DEBIAN_FRONTEND=noninteractive apt-get update
}

apt_install() {
  as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

apt_remove() {
  as_root env DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y "$@"
  as_root env DEBIAN_FRONTEND=noninteractive apt-get autoremove -y
}

install_vscode_repo() {
  need_cmd curl
  need_cmd gpg
  ensure_sudo

  local tmp_key
  tmp_key=$(mktemp -t microsoft-key.XXXXXX)

  curl -fsSL "${VSCODE_KEY_URL}" -o "${tmp_key}"
  as_root install -d -m 0755 /usr/share/keyrings /etc/apt/sources.list.d
  gpg --dearmor <"${tmp_key}" | as_root tee "${VSCODE_KEYRING}" >/dev/null
  as_root chmod 0644 "${VSCODE_KEYRING}"
  rm -f "${tmp_key}"

  cat <<EOF | as_root tee "${VSCODE_SOURCE}" >/dev/null
Types: deb
URIs: ${VSCODE_REPO_URL}
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: ${VSCODE_KEYRING}
EOF
}

install_vscode() {
  ensure_chroot
  warn_display
  confirm "Install Visual Studio Code desktop into this writable chroot?" || return 0
  install_vscode_repo
  apt_update
  apt_install code
  log_action "installed vscode"
  say "VS Code is installed. Run 'code .' from inside a GUI-capable chroot shell."
  say "For GitHub sign-in, copy the displayed login URL or device code to a host browser if VS Code cannot open one automatically."
}

remove_vscode() {
  ensure_chroot
  confirm "Remove Visual Studio Code desktop from this chroot?" || return 0
  ensure_sudo
  if package_installed code; then
    apt_remove code
  fi
  as_root rm -f "${VSCODE_SOURCE}" "${VSCODE_KEYRING}"
  log_action "removed vscode"
  say "VS Code has been removed. User settings under /home may remain."
}

foxglove_deb_url() {
  if [[ -n "${FOXGLOVE_DEB_URL:-}" ]]; then
    say "${FOXGLOVE_DEB_URL}"
    return 0
  fi

  case "$(dpkg --print-architecture)" in
    amd64) say "https://get.foxglove.dev/desktop/latest/foxglove-studio-latest-linux-amd64.deb" ;;
    arm64) say "https://get.foxglove.dev/desktop/latest/foxglove-studio-latest-linux-arm64.deb" ;;
    *) die "Foxglove Desktop installer is not configured for architecture: $(dpkg --print-architecture)" ;;
  esac
}

install_foxglove() {
  ensure_chroot
  need_cmd curl
  ensure_sudo
  warn_display
  confirm "Install Foxglove Desktop into this writable chroot?" || return 0

  install_foxglove_package
  log_action "installed foxglove"
  say "Foxglove Desktop is installed. Run 'foxglove-studio' from inside a GUI-capable chroot shell."
}

install_foxglove_package() {
  need_cmd curl
  ensure_sudo

  local deb url
  url=$(foxglove_deb_url)
  deb=$(mktemp -t foxglove-studio.XXXXXX.deb)

  curl -fL "${url}" -o "${deb}"
  apt_update
  apt_install "${deb}"
  rm -f "${deb}"
}

remove_foxglove() {
  ensure_chroot
  confirm "Remove Foxglove Desktop from this chroot?" || return 0
  ensure_sudo
  if package_installed foxglove-studio; then
    apt_remove foxglove-studio
  fi
  log_action "removed foxglove"
  say "Foxglove Desktop has been removed. User settings under /home may remain."
}

install_firefox_repo() {
  need_cmd curl
  ensure_sudo

  as_root install -d -m 0755 /etc/apt/keyrings /etc/apt/sources.list.d /etc/apt/preferences.d
  curl -fsSL "${MOZILLA_KEY_URL}" | as_root tee "${MOZILLA_KEYRING}" >/dev/null
  as_root chmod 0644 "${MOZILLA_KEYRING}"

  cat <<EOF | as_root tee "${MOZILLA_SOURCE}" >/dev/null
Types: deb
URIs: ${MOZILLA_REPO_URL}
Suites: mozilla
Components: main
Signed-By: ${MOZILLA_KEYRING}
EOF

  cat <<EOF | as_root tee "${MOZILLA_PREFERENCES}" >/dev/null
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000
EOF
}

configure_firefox_default() {
  if command -v xdg-mime >/dev/null 2>&1; then
    xdg-mime default firefox.desktop text/html || true
    xdg-mime default firefox.desktop x-scheme-handler/http || true
    xdg-mime default firefox.desktop x-scheme-handler/https || true
  fi
  if command -v xdg-settings >/dev/null 2>&1; then
    xdg-settings set default-web-browser firefox.desktop >/dev/null 2>&1 || true
  fi
}

install_firefox() {
  ensure_chroot
  warn_display
  confirm "Install Firefox from Mozilla's apt repository into this writable chroot?" || return 0
  install_firefox_repo
  apt_update
  apt_install firefox xdg-utils
  configure_firefox_default
  log_action "installed firefox"
  say "Firefox is installed from Mozilla's apt repository. Run 'firefox' from inside a GUI-capable chroot shell."
}

remove_firefox() {
  ensure_chroot
  confirm "Remove Firefox and Mozilla apt repository files from this chroot?" || return 0
  ensure_sudo
  if package_installed firefox; then
    apt_remove firefox
  fi
  as_root rm -f "${MOZILLA_SOURCE}" "${MOZILLA_PREFERENCES}" "${MOZILLA_KEYRING}"
  log_action "removed firefox"
  say "Firefox has been removed. User browser profiles under /home may remain."
}

upgrade_tools() {
  ensure_chroot
  confirm "Upgrade installed optional desktop tools in this chroot?" || return 0
  ensure_sudo

  local upgraded=0
  if package_installed code; then
    install_vscode_repo
    apt_update
    apt_install --only-upgrade code
    upgraded=1
  fi
  if package_installed foxglove-studio; then
    install_foxglove_package
    upgraded=1
  fi
  if package_installed firefox; then
    install_firefox_repo
    apt_update
    apt_install --only-upgrade firefox
    upgraded=1
  fi
  if (( upgraded == 0 )); then
    say "No optional desktop tools are installed."
  else
    log_action "upgraded optional tools"
  fi
}

run_choice() {
  case "$1" in
    status) show_status ;;
    install-vscode) install_vscode ;;
    remove-vscode) remove_vscode ;;
    install-foxglove) install_foxglove ;;
    remove-foxglove) remove_foxglove ;;
    install-firefox) install_firefox ;;
    remove-firefox) remove_firefox ;;
    upgrade) upgrade_tools ;;
    quit) return 1 ;;
    *) die "Unknown menu choice: $1" ;;
  esac
}

whiptail_menu() {
  command -v whiptail >/dev/null 2>&1 || return 1
  [[ -t 1 ]] || return 1

  local choice
  while true; do
    choice=$(whiptail --title "ros2_config" --menu "Optional desktop tools" 20 76 10 \
      status "Show installed optional tools" \
      install-vscode "Install Visual Studio Code desktop" \
      remove-vscode "Remove Visual Studio Code desktop" \
      install-foxglove "Install Foxglove Desktop" \
      remove-foxglove "Remove Foxglove Desktop" \
      install-firefox "Install Firefox browser from Mozilla apt" \
      remove-firefox "Remove Firefox browser" \
      upgrade "Upgrade installed optional tools" \
      quit "Exit" \
      3>&1 1>&2 2>&3) || return 0
    if [[ "${choice}" == "status" ]]; then
      whiptail --title "ros2_config status" --msgbox "$(status_text)" 11 76
      continue
    fi
    run_choice "${choice}" || return 0
  done
}

text_menu() {
  while true; do
    say ""
    say "ros2_config: optional desktop tools"
    say "  1) Status"
    say "  2) Install VS Code desktop"
    say "  3) Remove VS Code desktop"
    say "  4) Install Foxglove Desktop"
    say "  5) Remove Foxglove Desktop"
    say "  6) Install Firefox browser"
    say "  7) Remove Firefox browser"
    say "  8) Upgrade installed optional tools"
    say "  0) Exit"
    printf 'Select: '
    local choice
    read -r choice || return 0
    case "${choice}" in
      1) run_choice status ;;
      2) run_choice install-vscode ;;
      3) run_choice remove-vscode ;;
      4) run_choice install-foxglove ;;
      5) run_choice remove-foxglove ;;
      6) run_choice install-firefox ;;
      7) run_choice remove-firefox ;;
      8) run_choice upgrade ;;
      0|q|quit) return 0 ;;
      *) say "Unknown choice: ${choice}" ;;
    esac
  done
}

menu() {
  ensure_chroot
  if whiptail_menu; then
    return 0
  fi
  show_status
  text_menu
}

main() {
  ASSUME_YES=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes) ASSUME_YES=1; shift ;;
      -h|--help) usage; return 0 ;;
      *) break ;;
    esac
  done

  local command=${1:-menu}
  shift || true
  case "${command}" in
    menu) menu ;;
    status) ensure_chroot; show_status ;;
    install)
      case "${1:-}" in
        vscode|code) install_vscode ;;
        foxglove|foxglove-studio) install_foxglove ;;
        firefox|browser) install_firefox ;;
        *) die "Usage: ${SCRIPT_NAME} install {vscode|foxglove|firefox}" ;;
      esac
      ;;
    remove|uninstall)
      case "${1:-}" in
        vscode|code) remove_vscode ;;
        foxglove|foxglove-studio) remove_foxglove ;;
        firefox|browser) remove_firefox ;;
        *) die "Usage: ${SCRIPT_NAME} remove {vscode|foxglove|firefox}" ;;
      esac
      ;;
    upgrade) upgrade_tools ;;
    help) usage ;;
    *) die "Unknown command: ${command}" ;;
  esac
}

main "$@"