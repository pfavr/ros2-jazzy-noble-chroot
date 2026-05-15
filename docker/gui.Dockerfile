# syntax=docker/dockerfile:1.7
ARG BASE_IMAGE=ros2-jazzy:extensions
FROM ${BASE_IMAGE}

ARG ROS_USER=ros2
ARG GUI_APT_PACKAGES="dbus-x11 mesa-utils ros-jazzy-rviz2 x11-apps xdg-utils"
ARG INSTALL_FIREFOX=0
ARG INSTALL_FOXGLOVE_DESKTOP=0
ARG INSTALL_VSCODE=0
ARG FOXGLOVE_DEB_URL=

ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-c"]

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
WORKDIR /opt/ros2_ws
