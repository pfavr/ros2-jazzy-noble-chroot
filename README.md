# ros2-jazzy-noble-chroot

Build and run ROS 2 Jazzy on Ubuntu 24.04 Noble with two supported paths: a
Docker-first layered image workflow based on official ROS binary images, and the
original source-built chroot workflow. The Docker path is the recommended
starting point for day-to-day development and deployment; the chroot path remains
available when you need to rebuild the full ROS underlay from source.

The default target is `ROS_DISTRO=jazzy` on `UBUNTU_CODENAME=noble`. Other combinations are not tested and may need different source manifests, apt sources, or rosdep handling.

## What this does

Docker-first path:

- Starts from official `ros:jazzy-ros-base-noble` binary images.
- Builds one multi-stage `docker/Dockerfile` with named base, dev, runtime,
  Jetson, bagtools, and GUI targets.
- Installs released ROS extensions such as Foxglove Bridge, xacro, and
  `rosx_introspection` with apt by default.
- Keeps source overlays available for private, unreleased, or patched packages.
- Provides split Compose files for desktop/laptop dev, GPU overlay, Jetson
  robot workflows, and bag replay.

Source-built chroot path:

- Bootstraps an Ubuntu Noble root filesystem under `rootfs/`.
- Installs ROS 2 Jazzy source-build dependencies inside the chroot.
- Creates a Python tools environment at `/opt/ros2_ws/venv` (colcon, vcstool, rosdep).
- Imports the ROS 2 Jazzy source manifest, plus the repository's extra source manifest, into `/opt/ros2_ws/src`.
- Builds ROS 2 from source into `/opt/ros2_ws/install`.
- Builds Foxglove Bridge, Foxglove messages, and xacro from source alongside ROS 2.
- Provides `./set_environment.sh` for entering a ROS-ready shell.

The checkout can live anywhere on the host. Inside the chroot, the ROS workspace always lives at `/opt/ros2_ws`, which keeps build paths stable across machines.

The repository is intentionally small: scripts, Docker definitions,
documentation, VS Code settings, and license text. Generated root filesystems,
archives, build logs, and ROS source checkouts stay out of Git.

## Quick start

### Docker-first layered images

Install Docker Engine with Buildx and the Compose plugin, then build the default
binary-apt image stack:

```bash
./docker/build.sh all
```

Smoke-test the extension image:

```bash
./docker/smoke-test.sh
```

Enter a ROS-ready shell with the same host networking, IPC, X11, GPU, and
persistent-container behavior as the sourcebuilt Docker helper:

```bash
./docker/run.sh
```

Run common services with Compose:

```bash
docker compose -f docker/compose.dev.yml run --rm dev
docker compose -f docker/compose.dev.yml up -d foxglove-bridge
docker compose -f docker/compose.bag.yml run --rm bagtools
```

On NVIDIA desktop hosts, install and configure the NVIDIA Container Toolkit,
then validate GPU access with:

```bash
make gpu-check
```

For Jetson field development and runtime:

```bash
./docker/build.sh jetson-dev-arm64 robot-runtime-arm64
docker compose -f docker/compose.robot.yml run --rm jetson-dev
docker compose -f docker/compose.robot.yml up -d robot-runtime foxglove-bridge
```

The Docker workflow uses fixed ROS domain conventions: `10` for development,
`20` for robot field tests, `30` for simulation, and `40` for bag replay.

The normal Docker workflow does not produce one tarball per layer. Docker stores
and reuses layers internally. Use image tags and a registry when possible; use
`docker save` only when you need offline transfer of a complete image.

### Source-built chroot

Install host prerequisites first. On Debian/Ubuntu hosts:

```bash
sudo apt update
sudo apt install -y debootstrap zstd
```

`zstd` is needed for the default artifact-producing build. It is optional only
when you use `./build_all.sh --no-artifacts` and do not need to pack or unpack
compressed rootfs archives.

Then run the full release build. This builds ROS 2, runs the smoke test, and
packs a redistributable rootfs archive under `artifacts/`:

```bash
./build_all.sh
```

For an incremental development build, skip packaging and use colcon's
`--symlink-install` layout:

```bash
./build_all.sh --no-artifacts
```

The equivalent manual sequence for the default release flow is:

```bash
./scripts/check-host.sh
./scripts/create-rootfs.sh
./scripts/provision-rootfs.sh
./scripts/fetch-sources.sh
./scripts/build-ros2.sh
./scripts/smoke-test.sh
./scripts/pack-rootfs.sh
```

The full source build is large and can take several hours. For the default
release flow, plan for tens of gigabytes of free disk space for the rootfs,
source checkout, build tree, install tree, logs, and compressed artifact. More
RAM allows higher parallelism, but the defaults are intentionally moderate; if
the build machine starts swapping, lower `WORKERS` or `BUILD_JOBS`.

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

Check the extra tools in the source-built chroot:

```bash
ros2 pkg prefix foxglove_bridge
ros2 pkg prefix foxglove_msgs
ros2 pkg executables foxglove_bridge
ros2 run xacro xacro --help
```

Optional desktop tools such as VS Code, Foxglove Desktop, and Firefox are not installed by default. From inside the chroot, run the optional tools menu when you want them:

```bash
ros2_config
```

## Layout

Host checkout:

```text
.
├── rootfs/                 # Ubuntu Noble chroot, not committed
├── artifacts/              # Optional packed rootfs archives, not committed
├── docker/                 # Dockerfile, Compose files, and Docker helpers
├── src/                    # Project ROS 2 source workspace
├── configs/                # Robot, simulation, and replay configs
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
| `build_all.sh` | Run the complete check, create, provision, fetch, build, smoke-test, and rootfs-packaging flow. Use `--no-artifacts` for an incremental dev build without packing. |
| `clean_all.sh` | Remove generated rootfs, logs, and artifacts. Use `--keep-artifacts` to retain packed rootfs archives. |

Lower-level scripts:

| Script | Purpose |
| --- | --- |
| `scripts/check-host.sh` | Check host architecture and required commands. |
| `scripts/create-rootfs.sh` | Bootstrap Ubuntu Noble into `rootfs/`. |
| `scripts/provision-rootfs.sh` | Install chroot build tools, ROS apt source, venv tools, and rosdep data. |
| `scripts/fetch-sources.sh` | Import ROS 2 Jazzy repositories and repo-local extra source repositories with `vcstool`. |
| `scripts/install-rosdeps.sh` | Install source package dependencies with `rosdep`. |
| `scripts/build-ros2.sh` | Build ROS 2 with colcon. |
| `scripts/smoke-test.sh` | Verify `ros2`, demo executables, extra source packages, and `PyKDL`. |
| `scripts/ros2-config.sh` | Installed inside the rootfs as `/usr/local/bin/ros2_config`; install, remove, upgrade, and inspect optional desktop tools. |
| `scripts/pack-rootfs.sh` | Archive a finished rootfs into `artifacts/` as a self-contained `<stem>.tar.zst` (rootfs with `ros2-chroot.sh` baked in at `/usr/local/bin/`, plus a top-level symlink and metadata). |
| `scripts/unpack-rootfs.sh` | Restore a packed rootfs archive (in-tree convenience wrapper). |
| `scripts/ros2-chroot.sh` | Installed inside the rootfs at `/usr/local/bin/ros2-chroot.sh` by `provision-rootfs.sh`; exposed at the top of each packed artifact via a symlink. The recipient's daily entry point into the chroot. |
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

It then imports the repo-local extra source manifest from:

```text
ros2-extra.repos
```

That manifest pins the source-built extras that are not part of the upstream ROS 2 manifest: Foxglove Bridge, Foxglove messages, `rosx_introspection`, and xacro. Disable it with `ROS2_EXTRA_REPOS_FILE=` or point it at another host-side file:

```bash
ROS2_EXTRA_REPOS_FILE=/path/to/my-extra.repos ./scripts/fetch-sources.sh
```

Append additional chroot-visible manifest paths or URLs with `ROS2_EXTRA_REPOS_URLS`:

```bash
ROS2_EXTRA_REPOS_URLS='https://example.invalid/other.repos /tmp/local-extra.repos' ./scripts/fetch-sources.sh
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

## Optional desktop tools

VS Code and Foxglove Desktop are deliberately left out of the base rootfs and packed artifacts. They are useful for some workflows, but they are large and can be installed later inside the writable chroot.

Enter the ROS-ready shell, then run the menu:

```bash
./set_environment.sh
ros2_config
```

The menu can install all missing desktop tools, or select several tools to
install in one pass.

The same tool has direct commands for scripted use:

```bash
ros2_config status
ros2_config install all
ros2_config install vscode firefox
ros2_config install vscode
ros2_config install foxglove
ros2_config install firefox
ros2_config remove vscode
ros2_config remove foxglove
ros2_config remove firefox
```

`ros2_config install vscode` uses Microsoft's official `code` apt repository. `ros2_config install foxglove` downloads Foxglove Desktop's current Linux `.deb` for the chroot architecture; set `FOXGLOVE_DEB_URL` to use a pinned release or local mirror. `ros2_config install firefox` uses Mozilla's official apt repository with apt pinning, avoiding Ubuntu's snap-based browser packages.

GUI launch needs a host display. The packed artifact entry point, `ros2-chroot.sh`, forwards `DISPLAY` and `XAUTHORITY` when they are available, so desktop apps can run over a local X11 session or SSH X forwarding. If you install optional tools before packing an artifact, those tools become part of that artifact.

VS Code GitHub sign-in may not open your host browser automatically from inside the chroot. `ros2-chroot.sh` forwards X11 for GUI windows, but it does not connect the chroot to the host desktop's URL handlers, browser, or portal/session bus. Use the login URL or device code that VS Code displays and open it in a host browser, or run `ros2_config install firefox` and use Firefox inside the chroot.

## Python environment

The venv inside the chroot is created with `--system-site-packages`. This is intentional: ROS packages supplied by Ubuntu, especially `PyKDL`, need to be visible to the build and runtime environment.

Python command-line tooling (`colcon`, `vcstool`, `rosdep`) is installed into `/opt/ros2_ws/venv` with `pip install --no-deps`, so their transitive deps (`catkin_pkg`, `rosdistro`, `PyYAML`, ...) resolve against the apt-provided `python3-*` packages rather than pip-built duplicates.

## Portable artifacts

The Git repository should contain scripts and documentation, not `rootfs/`, `build/`, `install/`, or other generated artifacts.

To archive a finished rootfs:

```bash
./scripts/pack-rootfs.sh
```

This writes a single self-contained tarball into `artifacts/`:

```text
artifacts/ros2-jazzy-noble-rootfs-YYYYMMDD.tar.zst
```

To create a Docker-friendly rootfs archive from the same built environment:

```bash
./scripts/pack-docker.sh
```

Extracting it produces a date-stamped directory with everything the recipient needs:

```text
ros2-jazzy-noble-rootfs-YYYYMMDD/
├── rootfs/                                       # the chroot contents
├── ros2-chroot.sh -> rootfs/usr/local/bin/ros2-chroot.sh   # daily entry point (symlink)
├── README.md                                     # short usage instructions
└── ARTIFACT_INFO                                 # ROS distro, codename, build date, arch
```

The entry-point script lives inside the rootfs at `/usr/local/bin/ros2-chroot.sh` (single source of truth, also on `$PATH` after entering the chroot); the top-level `ros2-chroot.sh` is a relative symlink for ergonomics.

On a fresh amd64 host with `sudo`, `tar`, `zstd`, and chroot support, the recipient does not need to clone this repository:

```bash
sudo tar xf ros2-jazzy-noble-rootfs-YYYYMMDD.tar.zst   # sudo preserves ownership of in-chroot files
cd ros2-jazzy-noble-rootfs-YYYYMMDD
sudo ./ros2-chroot.sh smoke-test   # one-time verification: ros2 CLI + talker + PyKDL
sudo ./ros2-chroot.sh              # enter the ROS shell (default action)
```

After that, the everyday command after a reboot or in a new terminal is simply:

```bash
cd ros2-jazzy-noble-rootfs-YYYYMMDD && sudo ./ros2-chroot.sh
```

### Legacy sourcebuilt Docker artifact

The recommended Docker workflow lives under `docker/` and uses official ROS
binary images as reusable layers. The packaging flow below is still useful when
you specifically need to turn the source-built chroot into a Docker image.

`scripts/pack-docker.sh` writes four files under `artifacts/`:

```text
artifacts/ros2-jazzy-noble-docker.tar.zst
artifacts/ros2-jazzy-noble-docker.Dockerfile
artifacts/ros2-jazzy-noble-docker-run.sh
artifacts/ros2-jazzy-noble-install-docker-debian.sh
```

The Docker tarball has the root filesystem at archive root and includes
`/usr/local/bin/ros2-docker-entrypoint.sh`, which activates
`/opt/ros2_ws/venv`, sources `/opt/ros2_ws/install/local_setup.bash`, and then
runs the requested command. The chroot artifact and Docker artifact are built
from the same rootfs; optional tools already installed with `ros2_config` are
included in both.

Copy these generated files to the Docker host:

```text
ros2-jazzy-noble-docker.tar.zst
ros2-jazzy-noble-docker.Dockerfile
ros2-jazzy-noble-docker-run.sh
ros2-jazzy-noble-install-docker-debian.sh
```

On a fresh Debian Trixie host, or a Debian sid host where you want to use
Docker's Trixie apt repository, install Docker first:

```bash
sudo ./ros2-jazzy-noble-install-docker-debian.sh
```

The installer adds Docker's official apt repository, installs Docker Engine,
Buildx, and the Compose plugin, and adds the invoking user to the `docker`
group. Log out and back in, or run `newgrp docker`, before using `docker`
without `sudo`. Override the Docker repository codename when needed:

```bash
sudo ./ros2-jazzy-noble-install-docker-debian.sh --codename trixie
```

The most direct load path is `docker import` from the decompressed rootfs tar
stream:

```bash
zstd -dc ros2-jazzy-noble-docker.tar.zst | docker import \
  --change 'ENTRYPOINT ["/usr/local/bin/ros2-docker-entrypoint.sh"]' \
  --change 'CMD ["bash"]' \
  --change 'USER ros2' \
  --change 'WORKDIR /opt/ros2_ws' \
  --change 'ENV ROS_DISTRO=jazzy ROS_VERSION=2 ROS_PYTHON_VERSION=3 LANG=C.UTF-8 LC_ALL=C.UTF-8' \
  - ros2-jazzy-noble:sourcebuilt
```

For a one-off throwaway container, run Docker directly with ROS-friendly host
integration:

```bash
docker run --rm -it --network=host --ipc=host --init ros2-jazzy-noble:sourcebuilt
```

For day-to-day use, use the generated run helper. It adds the same ROS-friendly
Docker flags plus X11 GUI forwarding, and by default it creates or reuses a
persistent container named `ros2-jazzy-noble-sourcebuilt`, so changes made
inside the container are still there next time:

```bash
./ros2-jazzy-noble-docker-run.sh
```

Remove the persistent container when you want a fresh filesystem, or opt into
the old throwaway behavior for a single run:

```bash
docker rm -f ros2-jazzy-noble-sourcebuilt
ROS2_DOCKER_PERSIST=0 ./ros2-jazzy-noble-docker-run.sh
```

If your user is not in the `docker` group, running the helper with `sudo` is
supported; it will still look up the invoking user's Xauthority cookie for GUI
apps:

```bash
sudo ./ros2-jazzy-noble-docker-run.sh
```

Pass a command after the script name to run something specific:

```bash
./ros2-jazzy-noble-docker-run.sh rviz2
./ros2-jazzy-noble-docker-run.sh ros2 run demo_nodes_cpp talker
```

The helper uses the `ros2-jazzy-noble:sourcebuilt` image and
`ros2-jazzy-noble-sourcebuilt` container by default. Override them with
`ROS2_DOCKER_IMAGE` and `ROS2_DOCKER_CONTAINER` if you import or build with
another tag, or want separate persistent containers:

```bash
ROS2_DOCKER_IMAGE=my-ros2:test ROS2_DOCKER_CONTAINER=my-ros2-test ./ros2-jazzy-noble-docker-run.sh
```

The helper defaults to `--security-opt seccomp=unconfined`, which avoids common
Firefox and Electron sandbox failures in Docker. To use Docker's default seccomp
profile instead:

```bash
ROS2_DOCKER_SECCOMP=default ./ros2-jazzy-noble-docker-run.sh
```

`--network=host` lets DDS discovery and ROS 2 traffic use the host network
directly. `--ipc=host` makes the host shared-memory namespace visible too,
which matches the chroot's `/dev/shm` behavior and avoids common Fast DDS SHM
transport surprises.

Smoke-test the imported image:

```bash
docker run --rm --network=host --ipc=host --init ros2-jazzy-noble:sourcebuilt ros2 --help >/dev/null
docker run --rm --network=host --ipc=host --init ros2-jazzy-noble:sourcebuilt ros2 run demo_nodes_cpp talker
```

The generated Dockerfile is an alternative if you prefer a normal Docker build
from the same two files:

```bash
docker build -f ros2-jazzy-noble-docker.Dockerfile -t ros2-jazzy-noble:sourcebuilt .
```

The run helper is the preferred GUI path on an X11 desktop. The equivalent
manual throwaway command is:

```bash
docker run --rm -it --network=host --ipc=host --init \
  --security-opt seccomp=unconfined \
  -e DISPLAY \
  -e XAUTHORITY=/tmp/.ros2-docker.Xauthority \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v "$HOME/.Xauthority:/tmp/.ros2-docker.Xauthority:ro" \
  ros2-jazzy-noble:sourcebuilt
```

`ros2-chroot.sh` supports `enter | mount | umount | smoke-test | status | info | help`. `enter` is the default when no argument is given. Override the rootfs location with `ROOTFS_DIR=/srv/ros2/rootfs sudo -E ./ros2-chroot.sh`.

### Multiple terminals and safe cleanup

Every `enter` registers a per-pid session under `/run/ros2-chroot/<id>/` (host tmpfs). You can run the chroot from several terminals at once — `mount` is idempotent. On exit, the script reports the outcome:

* **Last session out** — support filesystems are unmounted automatically and the script tells you the rootfs tree is now safe to `rm -rf`.
* **Other sessions still active** — mounts are left in place; the message points you at `sudo ./ros2-chroot.sh status` to see who's still in.

`sudo ./ros2-chroot.sh status` shows pid/tty/user/start-time for every live session plus whether the support mounts are up. `umount` refuses while sessions are tracked as active; pass `--force` to override after a crash.

If you have this repository checked out and want to restore an artifact into the in-tree `rootfs/` for development, use:

```bash
sudo ./scripts/unpack-rootfs.sh artifacts/ros2-jazzy-noble-rootfs-YYYYMMDD.tar.zst
sudo ./scripts/smoke-test.sh
./set_environment.sh
```

`unpack-rootfs.sh` strips the artifact's `<stem>/rootfs/` prefix so the contents land at `./rootfs/` (the helper script, README, and ARTIFACT_INFO are not copied — the repo already has them).

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
