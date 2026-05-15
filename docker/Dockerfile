# syntax=docker/dockerfile:1.7
ARG ROS_BASE_IMAGE=ros:jazzy-ros-base-noble

FROM ${ROS_BASE_IMAGE} AS base

ARG ROS_USER=ros2
ARG ROS_UID=1000
ARG ROS_GID=1000
ARG BASE_APT_PACKAGES="bash-completion ca-certificates curl git iproute2 less locales lsb-release nano sudo vim-tiny"
ARG ROS_EXTENSION_PACKAGES="ros-jazzy-demo-nodes-cpp ros-jazzy-demo-nodes-py ros-jazzy-foxglove-bridge ros-jazzy-rosx-introspection ros-jazzy-xacro"

ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-c"]

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      ${BASE_APT_PACKAGES} \
      ${ROS_EXTENSION_PACKAGES} && \
    locale-gen en_US en_US.UTF-8 && \
    update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 && \
    rm -rf /var/lib/apt/lists/*

RUN primary_group="${ROS_USER}" && \
    if getent group "${ROS_USER}" >/dev/null; then \
      primary_group="${ROS_USER}"; \
    elif getent group "${ROS_GID}" >/dev/null; then \
      primary_group="$(getent group "${ROS_GID}" | cut -d: -f1)"; \
    else \
      groupadd --gid "${ROS_GID}" "${ROS_USER}"; \
    fi && \
    if id -u "${ROS_USER}" >/dev/null 2>&1; then \
      usermod --gid "${primary_group}" "${ROS_USER}"; \
    elif getent passwd "${ROS_UID}" >/dev/null; then \
      existing_user="$(getent passwd "${ROS_UID}" | cut -d: -f1)" && \
      usermod --login "${ROS_USER}" --home "/home/${ROS_USER}" --move-home "${existing_user}" && \
      usermod --gid "${primary_group}" "${ROS_USER}"; \
    else \
      useradd --uid "${ROS_UID}" --gid "${primary_group}" --create-home --shell /bin/bash "${ROS_USER}"; \
    fi && \
    usermod -aG sudo "${ROS_USER}" && \
    echo "${ROS_USER} ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/90-${ROS_USER}-nopasswd" && \
    chmod 0440 "/etc/sudoers.d/90-${ROS_USER}-nopasswd" && \
    install -d -o "${ROS_USER}" -g "${primary_group}" /opt/ros2_ws /opt/robot_ws /workspaces /bags /configs

COPY docker/entrypoint.sh /usr/local/bin/ros-entrypoint.sh
RUN chmod 0755 /usr/local/bin/ros-entrypoint.sh && \
    install -d -m 0755 /usr/local/share/ros-entrypoint.d

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    ROS_WORKSPACE=/workspaces/robot \
    ROS_DOMAIN_ID=10

USER ${ROS_USER}
WORKDIR /workspaces/robot
ENTRYPOINT ["/usr/local/bin/ros-entrypoint.sh"]
CMD ["bash"]

FROM base AS dev

ARG ROS_USER=ros2
ARG DEV_APT_PACKAGES="build-essential can-utils gdb htop i2c-tools iputils-ping net-tools openssh-client python3-pip python3-venv rsync tcpdump tree usbutils v4l-utils wget"

USER root
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends ${DEV_APT_PACKAGES} && \
    rm -rf /var/lib/apt/lists/*

USER ${ROS_USER}
WORKDIR /workspaces/robot

FROM dev AS builder

ARG ROS_USER=ros2
ARG APP_WS=/opt/robot_ws
ARG COLCON_WORKERS=4

USER root
RUN install -d -o "${ROS_USER}" -g "$(id -gn "${ROS_USER}")" "${APP_WS}/src"

USER ${ROS_USER}
WORKDIR ${APP_WS}
COPY --chown=${ROS_USER} src/ ${APP_WS}/src/

RUN if find src -mindepth 1 -name package.xml -print -quit | grep -q .; then \
      rosdep update --rosdistro "${ROS_DISTRO}" && \
      rosdep install --from-paths src --ignore-src -y --rosdistro "${ROS_DISTRO}" && \
      source "/opt/ros/${ROS_DISTRO}/setup.bash" && \
      colcon build --merge-install --parallel-workers "${COLCON_WORKERS}"; \
    else \
      mkdir -p install && \
      printf '%s\n' '# Empty workspace install placeholder.' > install/setup.bash; \
    fi

FROM base AS runtime

ARG ROS_USER=ros2
ARG APP_WS=/opt/robot_ws

USER root
COPY --from=builder --chown=${ROS_USER} ${APP_WS}/install ${APP_WS}/install
ENV ROS_DOMAIN_ID=10 \
    ROS_OVERLAY_SETUP_FILES=${APP_WS}/install/setup.bash:/workspaces/robot/install/setup.bash

USER ${ROS_USER}
WORKDIR ${APP_WS}

FROM dev AS jetson-dev

ARG ROS_USER=ros2
ENV ROS_DOMAIN_ID=20 \
    COLCON_DEFAULTS_FILE=/home/${ROS_USER}/.colcon/defaults.yaml

RUN mkdir -p "/home/${ROS_USER}/.colcon" && \
    printf '%s\n' \
      'build:' \
      '  parallel-workers: 2' \
      '  symlink-install: true' \
      > "/home/${ROS_USER}/.colcon/defaults.yaml"

WORKDIR /workspaces/robot

FROM runtime AS robot-runtime

ENV ROS_DOMAIN_ID=20
CMD ["bash", "-lc", "${ROBOT_LAUNCH_CMD:-ros2 launch robot_bringup robot.launch.py}"]

FROM dev AS bagtools

ARG ROS_USER=ros2
ARG BAGTOOLS_APT_PACKAGES="ros-jazzy-rosbag2 ros-jazzy-rosbag2-compression-zstd ros-jazzy-rosbag2-storage-mcap ros-jazzy-rosbag2-storage-sqlite3 sqlite3 zstd"

USER root
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends ${BAGTOOLS_APT_PACKAGES} && \
    rm -rf /var/lib/apt/lists/*

ENV ROS_DOMAIN_ID=40
USER ${ROS_USER}
WORKDIR /bags

FROM dev AS gui

ARG ROS_USER=ros2
ARG GUI_APT_PACKAGES="dbus-x11 mesa-utils ros-jazzy-rviz2 x11-apps xdg-utils"
ARG INSTALL_FIREFOX=0
ARG INSTALL_FOXGLOVE_DESKTOP=0
ARG INSTALL_VSCODE=0
ARG FOXGLOVE_DEB_URL=

USER root
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends ${GUI_APT_PACKAGES} && \
    rm -rf /var/lib/apt/lists/*

RUN if [[ "${INSTALL_FIREFOX}" == "1" ]]; then \
      install -d -m 0755 /etc/apt/keyrings /etc/apt/sources.list.d /etc/apt/preferences.d && \
      curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg -o /etc/apt/keyrings/packages.mozilla.org.asc && \
      chmod 0644 /etc/apt/keyrings/packages.mozilla.org.asc && \
      printf '%s\n' \
        'Types: deb' \
        'URIs: https://packages.mozilla.org/apt' \
        'Suites: mozilla' \
        'Components: main' \
        'Signed-By: /etc/apt/keyrings/packages.mozilla.org.asc' \
        > /etc/apt/sources.list.d/mozilla.sources && \
      printf '%s\n' \
        'Package: *' \
        'Pin: origin packages.mozilla.org' \
        'Pin-Priority: 1000' \
        > /etc/apt/preferences.d/mozilla && \
      apt-get update && \
      apt-get install -y --no-install-recommends firefox && \
      rm -rf /var/lib/apt/lists/*; \
    fi

RUN if [[ "${INSTALL_FOXGLOVE_DESKTOP}" == "1" ]]; then \
      arch="$(dpkg --print-architecture)" && \
      url="${FOXGLOVE_DEB_URL}" && \
      if [[ -z "${url}" ]]; then \
        case "${arch}" in \
          amd64) url=https://get.foxglove.dev/desktop/latest/foxglove-studio-latest-linux-amd64.deb ;; \
          arm64) url=https://get.foxglove.dev/desktop/latest/foxglove-studio-latest-linux-arm64.deb ;; \
          *) echo "Unsupported Foxglove Desktop architecture: ${arch}" >&2; exit 1 ;; \
        esac; \
      fi && \
      curl -fL "${url}" -o /tmp/foxglove-studio.deb && \
      apt-get update && \
      apt-get install -y --no-install-recommends /tmp/foxglove-studio.deb && \
      rm -f /tmp/foxglove-studio.deb && \
      rm -rf /var/lib/apt/lists/*; \
    fi

RUN if [[ "${INSTALL_VSCODE}" == "1" ]]; then \
      curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /usr/share/keyrings/microsoft.gpg && \
      chmod 0644 /usr/share/keyrings/microsoft.gpg && \
      printf '%s\n' \
        'Types: deb' \
        'URIs: https://packages.microsoft.com/repos/code' \
        'Suites: stable' \
        'Components: main' \
        'Architectures: amd64,arm64,armhf' \
        'Signed-By: /usr/share/keyrings/microsoft.gpg' \
        > /etc/apt/sources.list.d/vscode.sources && \
      apt-get update && \
      apt-get install -y --no-install-recommends code && \
      rm -rf /var/lib/apt/lists/*; \
    fi

USER ${ROS_USER}
WORKDIR /workspaces/robot
