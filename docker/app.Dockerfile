# syntax=docker/dockerfile:1.7
ARG EXTENSIONS_IMAGE=ros2-jazzy:extensions
ARG RUNTIME_IMAGE=${EXTENSIONS_IMAGE}

FROM ${EXTENSIONS_IMAGE} AS builder

ARG ROS_USER=ros2
ARG APP_WS=/opt/app_ws

USER root
RUN install -d -o "${ROS_USER}" -g "${ROS_USER}" "${APP_WS}/src"

USER ${ROS_USER}
WORKDIR ${APP_WS}

# Supply application source with BuildKit, for example:
#   docker buildx build --build-context app_src=/path/to/app_ws/src -f docker/app.Dockerfile .
COPY --from=app_src --chown=${ROS_USER}:${ROS_USER} / ${APP_WS}/src/

RUN rosdep update --rosdistro "${ROS_DISTRO}" && \
    rosdep install --from-paths src --ignore-src -y --rosdistro "${ROS_DISTRO}" && \
    source "/opt/ros/${ROS_DISTRO}/setup.bash" && \
    colcon build --merge-install --mixin release

FROM ${RUNTIME_IMAGE} AS runtime

ARG ROS_USER=ros2
ARG APP_WS=/opt/app_ws

USER root
COPY --from=builder --chown=${ROS_USER}:${ROS_USER} ${APP_WS}/install ${APP_WS}/install
ENV ROS_OVERLAY_SETUP_FILES=${APP_WS}/install/setup.bash:/opt/ros2_ws/install/setup.bash

USER ${ROS_USER}
WORKDIR ${APP_WS}
