#!/usr/bin/env bash
set -eo pipefail

if [[ -n "${ROS_DISTRO:-}" && -r "/opt/ros/${ROS_DISTRO}/setup.bash" ]]; then
  # shellcheck disable=SC1090
  source "/opt/ros/${ROS_DISTRO}/setup.bash"
elif [[ -r /opt/ros/jazzy/setup.bash ]]; then
  # shellcheck disable=SC1091
  source /opt/ros/jazzy/setup.bash
fi

default_overlay_setups="/workspaces/robot/install/setup.bash:/opt/robot_ws/install/setup.bash:/opt/app_ws/install/setup.bash:/opt/ros2_ws/install/setup.bash"
overlay_setups="${ROS_OVERLAY_SETUP_FILES:-${default_overlay_setups}}"

IFS=: read -r -a overlay_setup_array <<<"${overlay_setups}"
for overlay_setup in "${overlay_setup_array[@]}"; do
  if [[ -n "${overlay_setup}" && -r "${overlay_setup}" ]]; then
    # shellcheck disable=SC1090
    source "${overlay_setup}"
  fi
done

shopt -s nullglob
for hook in /usr/local/share/ros-entrypoint.d/*.sh; do
  if [[ -r "${hook}" ]]; then
    # shellcheck disable=SC1090
    source "${hook}"
  fi
done
shopt -u nullglob

if [[ $# -eq 0 ]]; then
  set -- bash
fi

exec "$@"
