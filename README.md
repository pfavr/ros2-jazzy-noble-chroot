# ros2-jazzy-noble-chroot

Build ROS 2 Jazzy from source inside an Ubuntu 24.04 Noble chroot, while keeping the host system mostly untouched. This was developed on Debian sid/forky, but the host can be any compatible amd64 Linux system with `sudo`, `debootstrap`, and chroot/mount support.

This is a Jazzy/Noble source-build workflow, not a Rolling workspace.

## What this does

- Creates an Ubuntu Noble root filesystem under `rootfs/`.
- Installs ROS 2 Jazzy source-build dependencies inside the chroot.
- Creates a Python tools environment at `/opt/ros2_ws/venv` inside the chroot.
- Imports ROS 2 Jazzy sources into `/opt/ros2_ws/src`.
- Builds ROS 2 from source into `/opt/ros2_ws/install`.
- Provides `./set_environment.sh` for entering a ROS-ready shell.

The checkout can live anywhere on the host. Inside the chroot, the ROS workspace always lives at `/opt/ros2_ws`, which keeps build paths stable across machines.

## Quick start

Install host prerequisites first. On Debian/Ubuntu hosts:

```bash
sudo apt update
sudo apt install -y debootstrap zstd
```

Then run:

```bash
./scripts/check-host.sh
./scripts/create-rootfs.sh
./scripts/provision-rootfs.sh
./scripts/fetch-sources.sh
./scripts/build-ros2.sh
./scripts/smoke-test.sh
```

Enter a ROS-ready shell:

```bash
./set_environment.sh
```

Try the demo nodes in two shells:

```bash
ros2 run demo_nodes_cpp talker
```

```bash
ros2 run demo_nodes_py listener
```

## Layout

Host checkout:

```text
.
├── rootfs/                 # Ubuntu Noble chroot, not committed
├── artifacts/              # Optional packed rootfs archives, not committed
├── scripts/                # Host orchestration scripts
└── set_environment.sh      # Enter a ROS-ready shell in the chroot
```

Inside the chroot:

```text
/opt/ros2_ws/
├── venv/                   # Python tooling environment
├── src/                    # ROS 2 Jazzy source checkout
├── build/
├── install/
└── log/
```

## Scripts

| Script | Purpose |
| --- | --- |
| `scripts/check-host.sh` | Check host architecture and required commands. |
| `scripts/create-rootfs.sh` | Bootstrap Ubuntu Noble into `rootfs/`. |
| `scripts/provision-rootfs.sh` | Install chroot build tools, ROS apt source, venv tools, and rosdep data. |
| `scripts/fetch-sources.sh` | Import ROS 2 Jazzy repositories with `vcstool`. |
| `scripts/install-rosdeps.sh` | Install source package dependencies with `rosdep`. |
| `scripts/build-ros2.sh` | Build ROS 2 with colcon. |
| `scripts/smoke-test.sh` | Verify `ros2`, demo executables, and `PyKDL`. |
| `scripts/pack-rootfs.sh` | Archive a finished rootfs into `artifacts/`. |
| `scripts/unpack-rootfs.sh` | Restore a packed rootfs archive. |
| `scripts/enter-rootfs.sh` | Enter the chroot as the internal `ros2` user. |
| `scripts/mount-rootfs.sh` | Bind/mount support filesystems for the chroot. |
| `scripts/umount-rootfs.sh` | Unmount chroot support filesystems. |

## Build tuning

The default build uses 4 colcon package workers and 8 compile jobs per package:

```bash
./scripts/build-ros2.sh
```

Override those defaults when needed:

```bash
WORKERS=6 BUILD_JOBS=8 ./scripts/build-ros2.sh
```

Avoid unconstrained 32-way package and compile parallelism. ROS 2 has large packages, and nested parallelism can make failures harder to diagnose.

## Python environment

The venv inside the chroot is created with `--system-site-packages`. This is intentional: ROS packages supplied by Ubuntu, especially `PyKDL`, need to be visible to the build and runtime environment.

Python command-line tooling such as `colcon`, `vcstool`, and `rosdep` is installed into `/opt/ros2_ws/venv`.

## Portable artifacts

The Git repository should contain scripts and documentation, not `rootfs/`, `build/`, `install/`, or other generated artifacts.

To archive a finished rootfs:

```bash
./scripts/pack-rootfs.sh
```

To restore it on another compatible amd64 host:

```bash
./scripts/unpack-rootfs.sh artifacts/ros2-jazzy-noble-rootfs-YYYYMMDD.tar.zst
./scripts/smoke-test.sh
./set_environment.sh
```

The chroot bundles userspace. It does not bundle the host kernel, GPU drivers, USB/serial permissions, udev rules, multicast/network policy, or realtime settings.

## VS Code notes

ROS source imports create many nested upstream Git repositories under `rootfs/opt/ros2_ws/src`. The workspace settings tell VS Code to ignore `rootfs/` and `artifacts/` for Git repository scanning, file watching, and search.

If VS Code has already discovered nested repositories, run:

```text
Ctrl+Shift+P -> Developer: Reload Window
```

## Verified locally

This workflow was verified on Debian forky/sid on 12 May 2026 with an Ubuntu Noble 24.04 chroot. ROS 2 Jazzy built successfully from source with 366 packages finished, and `scripts/smoke-test.sh` passed.

## License

This repository is licensed under the MIT License. See [LICENSE](LICENSE).
