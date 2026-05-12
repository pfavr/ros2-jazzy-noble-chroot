# ROS 2 Jazzy from source in an Ubuntu Noble chroot

This workspace builds ROS 2 Jazzy from source inside an Ubuntu 24.04 Noble chroot while the host remains Debian sid/forky.

The host checkout can live anywhere. Inside the chroot the ROS workspace always lives at `/opt/ros2_ws`, which keeps paths stable across machines.

## Layout

```text
.
├── rootfs/                 # Ubuntu Noble chroot, not committed
├── scripts/                # Host orchestration scripts
└── set_environment.sh      # Enter a ROS-ready shell in the chroot
```

Inside `rootfs`:

```text
/opt/ros2_ws/
├── venv/                   # Python tools environment
├── src/                    # ROS 2 Jazzy source checkout
├── build/
├── install/
└── log/
```

## Build flow

From the host checkout:

```bash
./scripts/create-rootfs.sh
./scripts/provision-rootfs.sh
./scripts/fetch-sources.sh
./scripts/build-ros2.sh
./scripts/smoke-test.sh
```

Then enter a ROS-ready shell:

```bash
./set_environment.sh
```

Inside that shell, verify the install:

```bash
ros2 --help
ros2 run demo_nodes_cpp talker
```

Use another `./set_environment.sh` shell for a listener:

```bash
ros2 run demo_nodes_py listener
```

## Host requirements

The host needs Linux amd64, `sudo`, `debootstrap`, and mount/chroot support. Build dependencies are installed inside the Ubuntu chroot, not on the Debian host.

The Python tools environment is `/opt/ros2_ws/venv` inside the chroot. It is created with `--system-site-packages` so ROS packages provided by Ubuntu, such as `PyKDL`, remain visible while `colcon`, `vcstool`, and `rosdep` are installed into the venv.

The default build uses 4 colcon workers and 8 compile jobs per package. Override these when needed:

```bash
WORKERS=6 BUILD_JOBS=8 ./scripts/build-ros2.sh
```

## Portability notes

The Git repository should contain these scripts and documentation, not the `rootfs` directory or build outputs. To move a finished build without recompiling, archive the chroot:

```bash
./scripts/pack-rootfs.sh
```

Restore the archive on another compatible Debian/Ubuntu amd64 host and use the same scripts from the checkout. Kernel, GPU, USB/serial device permissions, networking, and realtime settings still come from the host.

## Verified locally

This setup was verified on Debian forky/sid on 12 May 2026 with an Ubuntu Noble 24.04 chroot. ROS 2 Jazzy built successfully from source with 366 packages finished.
