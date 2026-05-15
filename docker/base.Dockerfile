# syntax=docker/dockerfile:1.7
ARG ROS_BASE_IMAGE=ros:jazzy-ros-base-noble
FROM ${ROS_BASE_IMAGE}

ARG ROS_USER=ros2
ARG ROS_UID=1000
ARG ROS_GID=1000

ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-c"]

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      bash-completion \
      ca-certificates \
      curl \
      git \
      iproute2 \
      less \
      locales \
      lsb-release \
      nano \
      sudo \
      vim-tiny && \
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
    install -d -o "${ROS_USER}" -g "${primary_group}" /opt/ros2_ws /workspaces

COPY docker/ros2-layer-entrypoint.sh /usr/local/bin/ros2-layer-entrypoint.sh
RUN chmod 0755 /usr/local/bin/ros2-layer-entrypoint.sh && \
    install -d -m 0755 /usr/local/share/ros2-layer-entrypoint.d

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    ROS_WORKSPACE=/opt/ros2_ws

USER ${ROS_USER}
WORKDIR /opt/ros2_ws
ENTRYPOINT ["/usr/local/bin/ros2-layer-entrypoint.sh"]
CMD ["bash"]
