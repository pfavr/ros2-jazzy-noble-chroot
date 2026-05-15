# Docker workflow

This directory contains the Docker-first workflow for desktop, laptop, server,
and Jetson use. The main image definition is one multi-stage Dockerfile with
named targets:

```text
base -> dev -> builder -> runtime
          |       |         |
          |       |         + robot-runtime
          |       + bagtools
          + jetson-dev
          + gui
```

The normal underlay is `ros:jazzy-ros-base-noble`. The source-built chroot image
remains a migration/reference path, not the production robot base.

## Build

Build the common amd64 stack for desktop/laptop/server work:

```bash
./docker/build.sh all
```

Build individual targets:

```bash
./docker/build.sh dev-amd64
./docker/build.sh runtime-amd64
./docker/build.sh bagtools-amd64
./docker/build.sh jetson-dev-arm64
./docker/build.sh robot-runtime-arm64
```

Images get convenience local tags such as `ros2-jazzy:dev` and immutable-style
tags such as `robot/ros2:robot-runtime-arm64-<gitsha>`. Set `ROS2_IMAGE_REPO` to
your registry path and `ROS2_DOCKER_PUSH=1` when pushing:

```bash
ROS2_IMAGE_REPO=registry.example.com/robot/ros2 ROS2_DOCKER_PUSH=1 \
  ./docker/build.sh robot-runtime-arm64
```

Do not deploy `latest` to robots. Use git-SHA tags for serious field tests.

## Desktop And Laptop Development

Open a dev shell with source mounted at `/workspaces/robot` and bags mounted at
`/bags`:

```bash
docker compose -f docker/compose.dev.yml run --rm dev
```

or:

```bash
make dev-shell
```

Inside the container:

```bash
colcon build --symlink-install
ros2 doctor
```

## GPU Desktop Overlay

Use the GPU overlay only on compatible NVIDIA desktop hosts:

```bash
docker compose -f docker/compose.dev.yml -f docker/compose.gpu.yml run --rm dev
```

or:

```bash
make gpu-shell
```

## VS Code Dev Containers

Open the repository in VS Code and choose **Reopen in Container**. The
devcontainer uses `docker/compose.dev.yml`, service `dev`, and workspace folder
`/workspaces/robot`. The GPU overlay is optional and is not required on the
laptop.

## Foxglove Bridge

Run Foxglove Bridge as a separate service instead of baking it into robot launch
files:

```bash
docker compose -f docker/compose.dev.yml up -d foxglove-bridge
```

or:

```bash
make foxglove
```

Default ROS domain IDs:

```text
10 = development
20 = robot field tests
30 = simulation
40 = bag replay/regression
```

## Jetson Field Development

Build or pull an arm64 Jetson development image, then run:

```bash
docker compose -f docker/compose.robot.yml run --rm jetson-dev
```

The Jetson dev service mounts the repo at `/workspaces/robot`, mounts host bags
at `/bags`, uses host networking and IPC, and is intentionally privileged for
early field development. Narrow device access later once the required hardware
set is known.

Inside the Jetson container:

```bash
colcon build --symlink-install --parallel-workers 2
```

Use `--parallel-workers 1` if the 8 GB Orin NX starts swapping.

## Robot Runtime

Robot runtime is separate from field development. It does not source-mount the
repo and should use immutable image tags:

```bash
ROBOT_LAUNCH_CMD='ros2 launch robot_bringup robot.launch.py' \
  docker compose -f docker/compose.robot.yml up -d robot-runtime foxglove-bridge
```

## Bags And Replay

Host bag path convention:

```text
/data/rosbags/YYYY-MM-DD/site/robot/run_id/
```

Container path:

```text
/bags
```

Open bagtools:

```bash
docker compose -f docker/compose.bag.yml run --rm bagtools
```

Replay with clock:

```bash
docker compose -f docker/compose.bag.yml run --rm bagtools \
  ros2 bag play /bags/YYYY-MM-DD/site/robot/run_id --clock
```

Replay configs live under `configs/replay` and should use `use_sim_time`.

## Jetson NVIDIA Caveats

Running Ubuntu 24.04 + ROS 2 Jazzy inside containers on a JetPack 6.x / Ubuntu
22.04-based host is an explicit validation item. Expected likely OK:

- ROS 2 nodes
- Python/C++ colcon builds
- Foxglove Bridge
- bag record/play
- networking
- serial/CAN/I2C with mounted devices

Test early and do not hide failures for:

- CUDA
- TensorRT
- cuDNN
- VPI
- camera/ISP stack
- hardware encoders/decoders
- anything depending on L4T userspace libraries

## Validation

Desktop/laptop:

```bash
docker compose -f docker/compose.dev.yml run --rm dev ros2 doctor
./docker/smoke-test.sh
```

GPU desktop:

```bash
docker compose -f docker/compose.dev.yml -f docker/compose.gpu.yml run --rm dev nvidia-smi
```

Jetson:

```bash
docker compose -f docker/compose.robot.yml run --rm jetson-dev ros2 run demo_nodes_cpp talker
docker compose -f docker/compose.robot.yml up -d foxglove-bridge
```

Backend/server bag replay:

```bash
docker compose -f docker/compose.bag.yml run --rm bagtools ros2 bag info /bags/path/to/bag
```
