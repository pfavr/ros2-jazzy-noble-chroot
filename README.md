# ros2-jazzy-noble-chroot

Build ROS 2 Jazzy from source inside an Ubuntu 24.04 Noble chroot, while keeping the host system mostly untouched. The host can be any amd64 Linux system with `sudo`, `debootstrap`, and chroot/mount support. Once built, the finished chroot can be packed into a compressed rootfs archive and restored on another amd64 host.

The default target is `ROS_DISTRO=jazzy` on `UBUNTU_CODENAME=noble`. Other combinations are not tested and may need different source manifests, apt sources, or rosdep handling.

## What this does

- Bootstraps an Ubuntu Noble root filesystem under `rootfs/`.
- Installs ROS 2 Jazzy source-build dependencies inside the chroot.
- Creates a Python tools environment at `/opt/ros2_ws/venv` (colcon, vcstool, rosdep).
- Imports the ROS 2 Jazzy source manifest into `/opt/ros2_ws/src`.
- Builds ROS 2 from source into `/opt/ros2_ws/install`.
- Provides `./set_environment.sh` for entering a ROS-ready shell.

The checkout can live anywhere on the host. Inside the chroot, the ROS workspace always lives at `/opt/ros2_ws`, which keeps build paths stable across machines.

The repository is intentionally small: scripts, documentation, VS Code settings, and license text. Generated root filesystems, archives, build logs, and ROS source checkouts stay out of Git.

## Quick start

Install host prerequisites first. On Debian/Ubuntu hosts:

```bash
sudo apt update
sudo apt install -y debootstrap
```

`zstd` is optional unless you want to pack or unpack compressed rootfs archives.

Then run the full build:

```bash
./build_all.sh
```

To also create a redistributable rootfs archive under `artifacts/` after the smoke test passes:

```bash
./build_all.sh --artifacts
```

The equivalent manual sequence is:

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
├── logs/                   # Per-step build_all.sh logs, not committed
├── build_all.sh            # Run the full build and smoke test
├── clean_all.sh            # Remove generated files and return to a clone-clean tree
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
| `build_all.sh` | Run the complete check, create, provision, fetch, build, and smoke-test flow. Use `--artifacts` to pack the finished rootfs. |
| `clean_all.sh` | Remove generated rootfs, logs, and artifacts. Use `--keep-artifacts` to retain packed rootfs archives. |

Lower-level scripts:

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
| `scripts/clean-rootfs.sh` | Safely unmount and remove the generated rootfs and local build logs. |
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

Avoid unconstrained 32-way package and compile parallelism. ROS 2 has large packages, and nested parallelism makes failures harder to diagnose and can exhaust memory.

## Reproducibility knobs

By default, `scripts/fetch-sources.sh` imports the live ROS 2 Jazzy manifest from:

```text
https://raw.githubusercontent.com/ros2/ros2/jazzy/ros2.repos
```

For repeatable rebuilds, save a known-good manifest and point the fetch step at it. The path or URL is consumed from inside the chroot, so use a URL or copy the file into `rootfs/` first:

```bash
sudo cp pinned-ros2.repos rootfs/tmp/pinned-ros2.repos
ROS2_REPOS_URL=/tmp/pinned-ros2.repos ./scripts/fetch-sources.sh
```

The ROS apt source package is downloaded from the latest `ros-apt-source` GitHub release by default, via an unauthenticated API call that is rate-limited. Pin it when you need an exact rebuild or hit the rate limit:

```bash
ROS_APT_SOURCE_VERSION='RELEASE_TAG' ./scripts/provision-rootfs.sh
```

The Ubuntu mirror defaults to `http://archive.ubuntu.com/ubuntu`. Point `UBUNTU_MIRROR` at a closer mirror for faster bootstrapping:

```bash
UBUNTU_MIRROR='http://gb.archive.ubuntu.com/ubuntu' ./scripts/create-rootfs.sh
```

If rosdep gains or loses keys over time, override the skipped keys without editing the script:

```bash
ROSDEP_SKIP_KEYS="fastcdr rti-connext-dds-6.0.1 urdfdom_headers" ./scripts/install-rosdeps.sh
```

## Python environment

The venv inside the chroot is created with `--system-site-packages`. This is intentional: ROS packages supplied by Ubuntu, especially `PyKDL`, need to be visible to the build and runtime environment.

Python command-line tooling (`colcon`, `vcstool`, `rosdep`) is installed into `/opt/ros2_ws/venv` with `pip install --no-deps`, so their transitive deps (`catkin_pkg`, `rosdistro`, `PyYAML`, ...) resolve against the apt-provided `python3-*` packages rather than pip-built duplicates.

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

## Operational notes

Most scripts re-exec themselves with `sudo` when needed. They bind-mount `/dev`, `/dev/pts`, `/proc`, `/sys`, and `/run` into the chroot before operating.

`build_all.sh` writes per-step logs to `logs/<step>.log` (e.g. `logs/build-ros2.log`). On failure, the script reports which step exited non-zero and where its log lives. `clean_all.sh` (and `scripts/clean-rootfs.sh`) only removes the logs from known step names, so any other `*.log` files you keep in the repo root are left alone.

If a script is interrupted, clean up support mounts before moving, deleting, packing, or unpacking the rootfs:

```bash
./scripts/umount-rootfs.sh
```

To remove all generated files and return to a clone-clean tree, use:

```bash
./clean_all.sh
```

Use `--keep-artifacts` when you want to retain packed rootfs archives:

```bash
./clean_all.sh --keep-artifacts
```

For lower-level cleanup, use the guarded rootfs cleanup script instead of deleting `rootfs/` directly:

```bash
./scripts/clean-rootfs.sh
```

Add `--artifacts` when you also want that lower-level script to remove packed rootfs archives.

The full source build is large and can take a long time. Keep enough free disk space for the rootfs, ROS source checkout, build tree, install tree, logs, and any packed archive.

The scripts perform basic step checks and will point back to the prerequisite step when expected files are missing.

## VS Code notes

ROS source imports create many nested upstream Git repositories under `rootfs/opt/ros2_ws/src`. The workspace settings tell VS Code to ignore `rootfs/` and `artifacts/` for Git repository scanning, file watching, and search.

If VS Code has already discovered nested repositories, run:

```text
Ctrl+Shift+P -> Developer: Reload Window
```

## Verified locally

Last verified on Debian forky/sid on 12 May 2026 with an Ubuntu Noble 24.04 chroot. ROS 2 Jazzy built successfully from source with 366 packages finished, and `scripts/smoke-test.sh` passed.

## License

This repository is licensed under the MIT License. See [LICENSE](LICENSE).
