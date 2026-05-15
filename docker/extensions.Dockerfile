# syntax=docker/dockerfile:1.7
ARG BASE_IMAGE=ros2-jazzy:base
FROM ${BASE_IMAGE} AS apt

ARG ROS_USER=ros2
ARG EXTENSION_APT_PACKAGES="ros-jazzy-demo-nodes-cpp ros-jazzy-demo-nodes-py ros-jazzy-foxglove-bridge ros-jazzy-rosx-introspection ros-jazzy-xacro"

ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-c"]

USER root
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends ${EXTENSION_APT_PACKAGES} && \
    rm -rf /var/lib/apt/lists/*

USER ${ROS_USER}
WORKDIR /opt/ros2_ws

FROM apt AS source-builder

ARG ROS_USER=ros2
ARG OVERLAY_WS=/opt/source_overlay_ws

USER root
RUN install -d -o "${ROS_USER}" -g "${ROS_USER}" "${OVERLAY_WS}"

USER ${ROS_USER}
WORKDIR ${OVERLAY_WS}
COPY --chown=${ROS_USER}:${ROS_USER} ros2-extra.repos /tmp/ros2-extra.repos

RUN mkdir -p src && \
    vcs import src < /tmp/ros2-extra.repos && \
    rosdep update --rosdistro "${ROS_DISTRO}" && \
    rosdep install --from-paths src --ignore-src -y --rosdistro "${ROS_DISTRO}" && \
    source "/opt/ros/${ROS_DISTRO}/setup.bash" && \
    colcon build --merge-install --mixin release

FROM apt AS source

ARG ROS_USER=ros2
ARG OVERLAY_WS=/opt/source_overlay_ws

USER root
COPY --from=source-builder --chown=${ROS_USER}:${ROS_USER} ${OVERLAY_WS}/install /opt/ros2_ws/install
ENV ROS_OVERLAY_SETUP_FILES=/opt/ros2_ws/install/setup.bash

USER ${ROS_USER}
WORKDIR /opt/ros2_ws
