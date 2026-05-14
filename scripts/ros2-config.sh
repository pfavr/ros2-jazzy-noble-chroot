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
  install all            Install all missing optional desktop tools.
  install TOOL [...]     Install one or more tools: vscode, foxglove, firefox.
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

tool_package() {
  case "$1" in
    vscode) say code ;;
    foxglove) say foxglove-studio ;;
    firefox) say firefox ;;
    *) die "Unknown optional tool: $1" ;;
  esac
}

tool_label() {
  case "$1" in
    vscode) say "VS Code desktop" ;;
    foxglove) say "Foxglove Desktop" ;;
    firefox) say "Firefox browser" ;;
    *) die "Unknown optional tool: $1" ;;
  esac
}

normalize_tool_name() {
  case "$1" in
    vscode|code) say vscode ;;
    foxglove|foxglove-studio) say foxglove ;;
    firefox|browser) say firefox ;;
    *) die "Unknown optional tool: $1" ;;
  esac
}

all_tools() {
  say vscode
  say foxglove
  say firefox
}

any_tool_missing() {
  ! package_installed code || ! package_installed foxglove-studio || ! package_installed firefox
}

installable_tool_entries() {
  local tool pkg label
  while IFS= read -r tool; do
    [[ -z "${tool}" ]] && continue
    pkg=$(tool_package "${tool}")
    if ! package_installed "${pkg}"; then
      label=$(tool_label "${tool}")
      printf '%s|%s|not installed\n' "${tool}" "${label}"
    fi
  done < <(all_tools)
}

install_tool_by_name() {
  case "$1" in
    vscode) install_vscode ;;
    foxglove) install_foxglove ;;
    firefox) install_firefox ;;
    *) die "Unknown optional tool: $1" ;;
  esac
}

join_labels() {
  local label joined=""
  for label in "$@"; do
    [[ -n "${joined}" ]] && joined+=", "
    joined+="${label}"
  done
  say "${joined}"
}

install_selected_tools() {
  ensure_chroot

  local requested tool normalized pkg label old_assume_yes summary
  local -a tools missing labels
  if (( $# == 0 )); then
    die "Usage: ${SCRIPT_NAME} install {vscode|foxglove|firefox|all}"
  fi

  for requested in "$@"; do
    if [[ "${requested}" == "all" ]]; then
      while IFS= read -r tool; do
        tools+=("${tool}")
      done < <(all_tools)
    else
      normalized=$(normalize_tool_name "${requested}")
      tools+=("${normalized}")
    fi
  done

  for tool in "${tools[@]}"; do
    pkg=$(tool_package "${tool}")
    label=$(tool_label "${tool}")
    if package_installed "${pkg}"; then
      say "${label} is already installed."
    else
      missing+=("${tool}")
      labels+=("${label}")
    fi
  done

  if (( ${#missing[@]} == 0 )); then
    say "Selected optional desktop tools are already installed."
    return 0
  fi

  summary=$(join_labels "${labels[@]}")
  confirm "Install ${summary} into this writable chroot?" || return 0

  old_assume_yes=${ASSUME_YES:-0}
  ASSUME_YES=1
  for tool in "${missing[@]}"; do
    install_tool_by_name "${tool}"
  done
  ASSUME_YES=${old_assume_yes}
}

confirm() {
  local prompt=$1
  if [[ "${ASSUME_YES:-0}" == "1" || ! -t 0 ]]; then
    return 0
  fi
  local answer
  read -r -p "${prompt} [Y/n] " answer
  [[ -z "${answer}" || "${answer}" == "y" || "${answer}" == "Y" || "${answer}" == "yes" || "${answer}" == "YES" ]]
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
    install-all) install_selected_tools all ;;
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

# Emits one line per tool: <action-key>|<menu label>|<description>
# action-key is the opposite of the current state (install-* or remove-*).
tool_menu_entries() {
  local pkg name action label desc version
  while IFS='|' read -r pkg name; do
    [[ -z "${pkg}" ]] && continue
    if package_installed "${pkg}"; then
      version=$(package_version "${pkg}")
      action="remove-${pkg}"
      label="Remove ${name}"
      desc="installed ${version}"
    else
      action="install-${pkg}"
      label="Install ${name}"
      desc="not installed"
    fi
    # Normalize action keys to the ones run_choice understands.
    case "${action}" in
      install-code) action=install-vscode ;;
      remove-code) action=remove-vscode ;;
      install-foxglove-studio) action=install-foxglove ;;
      remove-foxglove-studio) action=remove-foxglove ;;
    esac
    printf '%s|%s|%s\n' "${action}" "${label}" "${desc}"
  done <<'TOOLS'
code|VS Code desktop
foxglove-studio|Foxglove Desktop
firefox|Firefox browser
TOOLS
}

any_tool_installed() {
  package_installed code || package_installed foxglove-studio || package_installed firefox
}

whiptail_install_selected() {
  command -v whiptail >/dev/null 2>&1 || return 1
  [[ -t 1 ]] || return 1

  local entries selection tool label desc args
  local -a selected
  entries=$(installable_tool_entries)
  if [[ -z "${entries}" ]]; then
    say "All optional desktop tools are already installed."
    return 0
  fi

  args=(--title "ros2_config" --checklist "Select optional desktop tools to install" 20 76 10)
  while IFS='|' read -r tool label desc; do
    [[ -z "${tool}" ]] && continue
    args+=("${tool}" "${label} [${desc}]" ON)
  done <<<"${entries}"

  selection=$(whiptail "${args[@]}" 3>&1 1>&2 2>&3) || return 0
  selection=${selection//\"/}
  [[ -z "${selection}" ]] && return 0
  read -r -a selected <<<"${selection}"
  install_selected_tools "${selected[@]}"
}

text_install_selected() {
  local entries tool label desc choice token
  local idx=1
  local -a tools labels selected
  entries=$(installable_tool_entries)
  if [[ -z "${entries}" ]]; then
    say "All optional desktop tools are already installed."
    return 0
  fi

  say ""
  say "Install optional desktop tools"
  while IFS='|' read -r tool label desc; do
    [[ -z "${tool}" ]] && continue
    tools+=("${tool}")
    labels+=("${label}")
    printf '  %d) %-26s [%s]\n' "${idx}" "${label}" "${desc}"
    idx=$((idx + 1))
  done <<<"${entries}"
  say "  all) All missing optional tools"
  printf 'Select tools (Enter for all): '
  read -r choice || return 0
  choice=${choice//,/ }
  if [[ -z "${choice}" || "${choice}" == "all" ]]; then
    install_selected_tools all
    return 0
  fi

  for token in ${choice}; do
    if [[ "${token}" =~ ^[0-9]+$ && ${token} -ge 1 && ${token} -le ${#tools[@]} ]]; then
      selected+=("${tools[$((token - 1))]}")
    else
      selected+=("$(normalize_tool_name "${token}")")
    fi
  done

  install_selected_tools "${selected[@]}"
}

whiptail_menu() {
  command -v whiptail >/dev/null 2>&1 || return 1
  [[ -t 1 ]] || return 1

  local choice action label desc args entries
  while true; do
    args=(--title "ros2_config" --menu "Optional desktop tools" 20 76 10)
    entries=$(tool_menu_entries)
    while IFS='|' read -r action label desc; do
      [[ -z "${action}" ]] && continue
      args+=("${action}" "${label} [${desc}]")
    done <<<"${entries}"
    if any_tool_missing; then
      args+=(install-all "Install all missing optional tools")
      args+=(install-selected "Install selected optional tools")
    fi
    if any_tool_installed; then
      args+=(upgrade "Upgrade installed optional tools")
    fi
    args+=(quit "Exit")

    choice=$(whiptail "${args[@]}" 3>&1 1>&2 2>&3) || return 0
    if [[ "${choice}" == "install-selected" ]]; then
      whiptail_install_selected || return 0
      continue
    fi
    run_choice "${choice}" || return 0
  done
}

text_menu() {
  local action label desc entries line idx choice
  local -a actions labels descs
  while true; do
    actions=()
    labels=()
    descs=()
    entries=$(tool_menu_entries)
    while IFS='|' read -r action label desc; do
      [[ -z "${action}" ]] && continue
      actions+=("${action}")
      labels+=("${label}")
      descs+=("${desc}")
    done <<<"${entries}"

    say ""
    say "ros2_config: optional desktop tools"
    for idx in "${!actions[@]}"; do
      printf '  %d) %-26s [%s]\n' "$((idx + 1))" "${labels[$idx]}" "${descs[$idx]}"
    done
    local upgrade_idx=0
    local install_all_idx=0
    local install_selected_idx=0
    if any_tool_missing; then
      install_all_idx=$(( ${#actions[@]} + 1 ))
      printf '  %d) %s\n' "${install_all_idx}" "Install all missing optional tools"
      install_selected_idx=$(( ${#actions[@]} + 2 ))
      printf '  %d) %s\n' "${install_selected_idx}" "Install selected optional tools"
    fi
    if any_tool_installed; then
      upgrade_idx=$(( ${#actions[@]} + 1 ))
      (( install_selected_idx > 0 )) && upgrade_idx=$((install_selected_idx + 1))
      printf '  %d) %s\n' "${upgrade_idx}" "Upgrade installed optional tools"
    fi
    say "  0) Exit"
    printf 'Select: '
    read -r choice || return 0
    case "${choice}" in
      0|q|quit) return 0 ;;
      '') continue ;;
      *)
        if [[ "${choice}" =~ ^[0-9]+$ ]]; then
          if (( install_all_idx > 0 && choice == install_all_idx )); then
            run_choice install-all
            continue
          fi
          if (( install_selected_idx > 0 && choice == install_selected_idx )); then
            text_install_selected
            continue
          fi
          if (( upgrade_idx > 0 && choice == upgrade_idx )); then
            run_choice upgrade
            continue
          fi
          if (( choice >= 1 && choice <= ${#actions[@]} )); then
            run_choice "${actions[$((choice - 1))]}"
            continue
          fi
        fi
        say "Unknown choice: ${choice}"
        ;;
    esac
  done
}

menu() {
  ensure_chroot
  if whiptail_menu; then
    return 0
  fi
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
        all|vscode|code|foxglove|foxglove-studio|firefox|browser) install_selected_tools "$@" ;;
        *) die "Usage: ${SCRIPT_NAME} install {vscode|foxglove|firefox|all}" ;;
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