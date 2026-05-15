# Layered Docker workflow

This directory contains the Docker-first path for ROS 2 Jazzy on Ubuntu Noble.
It uses official ROS binary images as the underlay and keeps source builds only
for overlays that need private, unreleased, or patched packages.

## Image layers

```text
ros:jazzy-ros-base-noble
  -> ros2-jazzy:base
    -> ros2-jazzy:extensions
      -> ros2-jazzy:gui
      -> ros2-jazzy:app
```

- `base.Dockerfile` starts from the official ROS image and adds the project
  user, common shell/runtime packages, and an entrypoint that sources ROS plus
  optional overlay workspaces.
- `extensions.Dockerfile` installs released ROS extension packages with apt.
  It also has a `source` target for building `ros2-extra.repos` as an overlay
  when apt packages are not enough.
- `gui.Dockerfile` adds GUI/dev packages on top of the extension image.
- `app.Dockerfile` is a multi-stage template for a future application source
  workspace supplied as a BuildKit named context.
- `compose.yaml` defines common runtime, bridge, GUI, and development services.

Docker already stores and reuses image layers internally. Do not create one tar
file per layer during normal development. Use tags and a registry when possible;
use `docker save` tarballs only for offline image transfer.

## Build

Build the normal binary-apt stack:

```bash
./docker/build.sh all
```

Build only one image:

```bash
./docker/build.sh base
./docker/build.sh extensions
./docker/build.sh gui
```

Build the optional source-overlay extension image from `ros2-extra.repos`:

```bash
./docker/build.sh extensions-source
```

Build an application runtime image from an external ROS workspace source tree:

```bash
APP_SRC=/path/to/app_ws/src ./docker/build.sh app
```

By default the helper uses `docker buildx build --load`. Set
`ROS2_DOCKER_PUSH=1` to push instead of loading locally.

## Run

Use the thin wrapper when you want the same X11, host networking, IPC, GPU, and
persistent-container behavior as the existing sourcebuilt Docker helper:

```bash
./docker/run.sh
./docker/run.sh ros2 pkg list
./docker/run.sh --gui rviz2
./docker/run.sh --gui foxglove-studio
```

Use Compose for repeatable service-style launches:

```bash
docker compose -f docker/compose.yaml --profile runtime run --rm shell
docker compose -f docker/compose.yaml --profile runtime up bridge
docker compose -f docker/compose.yaml --profile dev run --rm dev
docker compose -f docker/compose.yaml --profile gui run --rm gui
```

The run wrapper is the preferred path for GUI applications because it handles
Xauthority setup more carefully than a static Compose file can.

`docker/run.sh` forwards `ROS_DOMAIN_ID` and `RMW_IMPLEMENTATION` when they are
set. For Compose launches, pass those variables explicitly with `docker compose
run -e ...` or add a local Compose override file for your robot/network setup.

## Smoke test

```bash
./docker/smoke-test.sh
ROS2_DOCKER_IMAGE=ros2-jazzy:gui ./docker/smoke-test.sh
```
