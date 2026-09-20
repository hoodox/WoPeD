# Convenience wrapper for the WoPeD + Xpra image (see ./Dockerfile).
#
#   make -C images help
#
# Password: the container password is XPRA_PASSWORD. It is read from .myenv/local (or your
# environment). Add this line to .myenv/local:
#   export XPRA_PASSWORD='choose-a-password'
# See .myenv/local.example. The value is never printed and is passed to Docker by name only (-e XPRA_PASSWORD).

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
REPO_ROOT    := $(abspath $(MAKEFILE_DIR)..)

WOPED_IMAGE          ?= woped-xpra
WOPED_JAVA_VERSION   ?= 17
WOPED_PORT           ?= 14500
WOPED_BIND           ?= 127.0.0.1
WOPED_CONTAINER      ?= woped
WOPED_HOME_VOLUME    ?= woped-home
WOPED_ENV_FILE       ?= $(REPO_ROOT)/.myenv/local
WOPED_M2_SETTINGS    ?=

# Default host folder for nets, mounted at /nets. WOPED_NETS_DIR (env file or command line) overrides it.
WOPED_DEFAULT_NETS_DIR := $(REPO_ROOT)/mynets

# Match the container user to the calling user so the mounted nets folder is writable.
HOST_UID := $(shell id -u)
HOST_GID := $(shell id -g)
ifeq ($(HOST_UID),0)
HOST_UID := 1000
HOST_GID := 1000
endif

SHELL       := /bin/bash
.SHELLFLAGS := -euo pipefail -c
.PHONY: help build run up down logs

# Load the env file silently (the existing .myenv/local echoes a token when sourced), require
# XPRA_PASSWORD, and resolve + create the host nets folder as $nets.
# Precedence: command line / caller's environment > env file > default.
PREPARE = pre_pw="$${XPRA_PASSWORD-}"; pre_nets="$${WOPED_NETS_DIR-}"; \
  if [ -f "$(WOPED_ENV_FILE)" ]; then set +u; set -a; . "$(WOPED_ENV_FILE)" >/dev/null 2>&1 || true; set +a; set -u; fi; \
  [ -z "$$pre_pw" ] || XPRA_PASSWORD="$$pre_pw"; [ -z "$$pre_nets" ] || WOPED_NETS_DIR="$$pre_nets"; \
  if [ -z "$${XPRA_PASSWORD:-}" ]; then \
    echo "XPRA_PASSWORD is not set. Add this line to $(WOPED_ENV_FILE) (see .myenv/local.example):" >&2; \
    echo "  export XPRA_PASSWORD='choose-a-password'" >&2; exit 1; fi; \
  export XPRA_PASSWORD; \
  nets="$${WOPED_NETS_DIR:-$(WOPED_DEFAULT_NETS_DIR)}"; case "$$nets" in /*) ;; *) nets="$(REPO_ROOT)/$$nets";; esac; \
  mkdir -p "$$nets"

RUN_ARGS = --rm --name $(WOPED_CONTAINER) -e XPRA_PASSWORD \
  -v "$$nets:/nets" -v "$(WOPED_HOME_VOLUME):/home/woped" -p $(WOPED_BIND):$(WOPED_PORT):14500 $(WOPED_IMAGE)

help:
	@printf '%s\n' \
	  'make build   build the image (gh must be logged in with read:packages, or WOPED_M2_SETTINGS=<settings.xml>)' \
	  'make run     run in the foreground, Ctrl-C stops it' \
	  'make up      run in the background' \
	  'make down    stop the background container' \
	  'make logs    follow the container log' \
	  '' \
	  'Variables (override like: make up WOPED_PORT=14600):' \
	  '  WOPED_IMAGE=$(WOPED_IMAGE)  WOPED_JAVA_VERSION=$(WOPED_JAVA_VERSION)  WOPED_PORT=$(WOPED_PORT)  WOPED_BIND=$(WOPED_BIND)  WOPED_CONTAINER=$(WOPED_CONTAINER)' \
	  '  WOPED_NETS_DIR   host folder mounted at /nets (default $(WOPED_DEFAULT_NETS_DIR)); may be set in the env file' \
	  '  WOPED_HOME_VOLUME=$(WOPED_HOME_VOLUME)   (WoPeD settings volume)' \
	  '  WOPED_ENV_FILE=$(WOPED_ENV_FILE)   (must export XPRA_PASSWORD, see .myenv/local.example)'

build:
	@f="$(WOPED_M2_SETTINGS)"; \
	if [ -z "$$f" ]; then \
	  command -v gh >/dev/null || { echo "gh not found: install it or pass WOPED_M2_SETTINGS=<settings.xml>" >&2; exit 1; }; \
	  f=$$(mktemp); trap 'rm -f "$$f"' EXIT; \
	  printf '<settings><servers><server><id>github</id><username>%s</username><password>%s</password></server></servers></settings>\n' \
	    "$$(gh api user --jq .login)" "$$(gh auth token)" > "$$f"; \
	fi; \
	DOCKER_BUILDKIT=1 docker build -f "$(MAKEFILE_DIR)Dockerfile" --secret id=m2settings,src="$$f" \
	  --build-arg JAVA_VERSION=$(WOPED_JAVA_VERSION) --build-arg WOPED_UID=$(HOST_UID) --build-arg WOPED_GID=$(HOST_GID) \
	  -t $(WOPED_IMAGE) "$(REPO_ROOT)"

run:
	@$(PREPARE); \
	echo "WoPeD: http://$(WOPED_BIND):$(WOPED_PORT)   nets folder: $$nets -> /nets   (Ctrl-C to stop)"; \
	docker run $(RUN_ARGS)

up:
	@$(PREPARE); \
	docker run -d $(RUN_ARGS) >/dev/null; \
	echo "WoPeD: http://$(WOPED_BIND):$(WOPED_PORT)   nets folder: $$nets -> /nets   (make down to stop)"

down:
	@docker stop $(WOPED_CONTAINER) >/dev/null 2>&1 && echo "stopped $(WOPED_CONTAINER)" || echo "$(WOPED_CONTAINER) is not running"

logs:
	@docker logs -f $(WOPED_CONTAINER)
