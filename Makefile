SHELL := /usr/bin/env bash

DOCKER_BUILD ?= ./docker/build.sh
COMPOSE_DEV := docker compose -f docker/compose.dev.yml
COMPOSE_GPU := docker compose -f docker/compose.dev.yml -f docker/compose.gpu.yml
COMPOSE_ROBOT := docker compose -f docker/compose.robot.yml
COMPOSE_BAG := docker compose -f docker/compose.bag.yml

.PHONY: help build-base build-dev-amd64 build-bagtools-amd64 build-jetson-dev-arm64 build-robot-runtime-arm64 build-runtime-amd64 build-gui-amd64 build-all dev-shell gpu-shell gpu-check foxglove robot-dev-shell robot-up robot-down bag-shell bag-play smoke

help:
	@printf '%s\n' \
	  'Targets:' \
	  '  build-all                 Build amd64 base/dev/runtime/gui/bagtools images' \
	  '  build-dev-amd64           Build desktop/laptop dev image' \
	  '  build-bagtools-amd64      Build bag replay/inspection image' \
	  '  build-jetson-dev-arm64    Build Jetson field-development image' \
	  '  build-robot-runtime-arm64 Build Jetson robot runtime image' \
	  '  dev-shell                 Open desktop/laptop dev shell' \
	  '  gpu-shell                 Open dev shell with NVIDIA GPU overlay' \
	  '  gpu-check                 Run nvidia-smi through the GPU Compose overlay' \
	  '  foxglove                  Run Foxglove Bridge service' \
	  '  robot-dev-shell           Open Jetson dev shell' \
	  '  robot-up                  Start robot-runtime and Foxglove Bridge' \
	  '  bag-shell                 Open bagtools shell' \
	  '  bag-play BAG=/bags/path   Replay a bag with --clock'

build-base:
	$(DOCKER_BUILD) base

build-dev-amd64:
	$(DOCKER_BUILD) dev-amd64

build-bagtools-amd64:
	$(DOCKER_BUILD) bagtools-amd64

build-jetson-dev-arm64:
	$(DOCKER_BUILD) jetson-dev-arm64

build-robot-runtime-arm64:
	$(DOCKER_BUILD) robot-runtime-arm64

build-runtime-amd64:
	$(DOCKER_BUILD) runtime-amd64

build-gui-amd64:
	$(DOCKER_BUILD) gui-amd64

build-all:
	$(DOCKER_BUILD) all

dev-shell:
	$(COMPOSE_DEV) run --rm dev

gpu-shell:
	$(COMPOSE_GPU) run --rm dev

gpu-check:
	$(COMPOSE_GPU) run --rm dev nvidia-smi

foxglove:
	$(COMPOSE_DEV) up -d foxglove-bridge

robot-dev-shell:
	$(COMPOSE_ROBOT) run --rm jetson-dev

robot-up:
	$(COMPOSE_ROBOT) up -d robot-runtime foxglove-bridge

robot-down:
	$(COMPOSE_ROBOT) down

bag-shell:
	$(COMPOSE_BAG) run --rm bagtools

bag-play:
	@test -n "$(BAG)" || { echo 'error: BAG=/bags/path is required'; exit 2; }
	$(COMPOSE_BAG) run --rm bagtools ros2 bag play "$(BAG)" --clock

smoke:
	./docker/smoke-test.sh
