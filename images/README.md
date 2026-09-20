# WoPeD in a browser (Docker + Xpra)

WoPeD is a Java Swing desktop program. This folder packages it in a Docker image that runs the
unchanged desktop app on a virtual screen and streams that screen to your browser with
[Xpra](https://xpra.org)'s HTML5 client. No WoPeD source code is changed.

```
Browser  <-- HTTP/WebSocket + password -->  Xpra  <-->  virtual display  <-->  WoPeD (Java)
```

One container is one WoPeD session. Closing WoPeD stops the container.

## Quick start

```bash
# 1. Put your password in .myenv/local (see "Settings" below)
echo "export XPRA_PASSWORD='choose-a-password'" >> .myenv/local

# 2. Build the image (first build takes a few minutes)
make -C images build

# 3. Run it, then open http://127.0.0.1:14500 and enter the password
make -C images up
make -C images down      # stop it
```

Your nets are saved to `<repo>/mynets` on the host (see "Saving nets on the host").

## Requirements

- Docker with BuildKit (the default builder in Docker 23 and later) and GNU `make`.
- To **build**: the [GitHub CLI](https://cli.github.com) logged in with the `read:packages`
  scope, because some WoPeD dependencies are hosted on GitHub Packages
  (`maven.pkg.github.com/woped/woped`). Add the scope with
  `gh auth refresh -h github.com -s read:packages`. Or pass your own Maven settings file:
  `make -C images build WOPED_M2_SETTINGS=/path/to/settings.xml` (it needs a `github` server
  entry with a token that has `read:packages`).
- To **run in the browser**: nothing but Docker and the image. To **run without Docker**, see "Running without Docker".

## Settings

`make` reads two settings from `.myenv/local` (copy `.myenv/local.example` for a template):

| Setting | Required | Meaning |
|---|---|---|
| `XPRA_PASSWORD` | yes | The password the browser asks for. There is no default: without it nothing starts. |
| `WOPED_NETS_DIR` | no | Host folder mounted at `/nets` in the container. Default: `<repo>/mynets`. |

`.myenv/` is git-ignored (only `local.example` is tracked), so your real values are not committed.
The file is sourced by a shell, so do not put `echo` lines in it that print secrets. `make` reads
it silently and passes only `XPRA_PASSWORD` into the container. Consider `chmod 600 .myenv/local`.

A value given on the command line or in your environment beats the file, which beats the default:
`make -C images up WOPED_NETS_DIR=~/my-nets`.

## Make targets

Run them from anywhere with `make -C images <target>` (or `cd images` first).

| Target | What it does |
|---|---|
| `build` | Build the image. Generates a temporary token file from `gh` and deletes it afterwards. |
| `run` | Run in the foreground; Ctrl-C stops it. |
| `up` | Run in the background and print the URL. |
| `down` | Stop the background container. |
| `logs` | Follow the container log. |
| `local-build` | Build the jar with **your own** Maven, no Docker (see "Running without Docker"). |
| `local` | Run WoPeD directly on this machine, no Docker and no Xpra. Builds first if there is no jar. |
| `help` | List targets and current variable values. |

Variables (override on the command line, e.g. `make -C images up WOPED_PORT=14600`):

| Variable | Default | Meaning |
|---|---|---|
| `WOPED_IMAGE` | `woped-xpra` | Image name (and tag). |
| `WOPED_JAVA_VERSION` | `17` | Java version used to build and run (see "Java version"). |
| `WOPED_PORT` | `14500` | Host port. |
| `WOPED_BIND` | `127.0.0.1` | Host address the port is published on. |
| `WOPED_CONTAINER` | `woped` | Container name (used by `down` and `logs`). |
| `WOPED_HOME_VOLUME` | `woped-home` | Docker volume for WoPeD's settings (`/home/woped`). |
| `WOPED_NETS_DIR` | `<repo>/mynets` | Host folder for nets (may be set in `.myenv/local`). |
| `WOPED_ENV_FILE` | `<repo>/.myenv/local` | File that provides `XPRA_PASSWORD`. |
| `WOPED_M2_SETTINGS` | (empty) | Use this Maven settings file instead of generating one from `gh`. |

These are all prefixed `WOPED_` on purpose: generic names such as `NAME` or `PORT` are often
already set in your shell and would silently override the defaults.

## Saving nets on the host

The host folder is mounted at `/nets` in the container. It is an **extra** location: WoPeD's own
default nets folder (`~/.WoPeD-<version>/nets` inside the settings volume) is left as it is.

- In WoPeD's Open/Save dialogs, browse to `/nets`.
- To make the dialogs start there, set `/nets` as the home directory in WoPeD's Configuration
  dialog once. WoPeD stores it in the settings volume when it exits.

The container user is uid/gid 1000 by default. `make build` builds the image with **your** uid
and gid so the mounted folder is writable. If you build by hand for a different user, pass
`--build-arg WOPED_UID=$(id -u) --build-arg WOPED_GID=$(id -g)`. If `/nets` is not writable, the
container prints a warning at startup (and still starts).

## Java version

The default is **Java 17**, which is what the project's own CI uses. **Java 21** builds and starts
WoPeD fine (only startup was tested, not every feature); Java 25 was not tried.

```bash
make -C images build WOPED_JAVA_VERSION=21 WOPED_IMAGE=woped-xpra:21
make -C images up    WOPED_IMAGE=woped-xpra:21
```

## Running without Docker

`make -C images local` starts WoPeD as a normal desktop app on your own machine, using your own
Java. It builds the jar first if there is none (`make -C images local-build` builds it explicitly,
and is how you rebuild after changing the code).

```bash
make -C images local
```

What you need: Maven 3.9+, a JDK/JRE 11 or newer (the project's CI uses 17; 21 was used to test this),
`gh` logged in with `read:packages` for the first build (or `WOPED_M2_SETTINGS`), and a display
(`DISPLAY` or `WAYLAND_DISPLAY`, which WSLg provides on WSL). It refuses to start with a clear message
if one is missing.

How it differs from the browser setup:

- **No password, no Xpra, no isolation.** It is an ordinary local desktop program.
- **No `/nets` mount.** WoPeD uses its normal settings folder `~/.WoPeD-<version>/` on your machine.
  `<repo>/mynets` is just a folder you can browse to in the Open/Save dialogs.
- **It changes your machine, not a container:** the build fills `~/.m2/repository`, and running it
  creates `~/.WoPeD-<version>/` plus a `woped.log` in the repo root (git-ignored).
- The build skips `WoPeD-Installer` and `WoPeD-UnitTests`, like the image does.

## Without make

From the repo root:

```bash
# build (settings.xml must contain a `github` server with a read:packages token)
docker build -f images/Dockerfile --secret id=m2settings,src=$HOME/.woped-m2-settings.xml -t woped-xpra .

# run
export XPRA_PASSWORD='choose-a-password'
mkdir -p mynets
docker run --rm -e XPRA_PASSWORD -v "$PWD/mynets:/nets" -v woped-home:/home/woped \
  -p 127.0.0.1:14500:14500 woped-xpra
```

## Security

- The password is enforced on the browser port itself (`--bind-tcp=...,auth=env`). This matters:
  Xpra's plain `--auth=env` option alone leaves the TCP port open. Missing and wrong passwords are
  rejected over both TCP and WebSocket.
- The connection is plain HTTP/WebSocket, so the password is **not encrypted** in transit. Keep the
  default `WOPED_BIND=127.0.0.1`. To reach it from elsewhere, put a TLS reverse proxy in front
  rather than publishing the port on a public address.
- The image is built with a GitHub token passed as a BuildKit **secret**: it is not stored in an
  image layer or in `docker history`. `.myenv/` and `.git` are excluded from the build context.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `XPRA_PASSWORD is not set` | Add `export XPRA_PASSWORD='...'` to `.myenv/local` (see `.myenv/local.example`). |
| Build fails with `401 Unauthorized` from `maven.pkg.github.com` | The token lacks `read:packages`. Run `gh auth refresh -h github.com -s read:packages`. If you use `WOPED_M2_SETTINGS`, regenerate that file, because a refresh changes the token. |
| Browser shows a dark page with a password box | That is the login prompt. Enter the password. |
| Container disappeared | You closed WoPeD; the container stops when WoPeD exits. Start it again with `make -C images up`. |
| `Warning: /nets is not writable` | The host folder is owned by a different user. Fix its owner, or rebuild with your uid/gid (see above). |
| `port is already allocated` | Something uses port 14500: `make -C images up WOPED_PORT=14600`. |
| Log lines about `libx264`, `paramiko` or DRM | Harmless. Xpra falls back to other encoders. |

## What is in this folder

| File | Purpose |
|---|---|
| `Dockerfile` | Two stages: a Maven + JDK build of WoPeD, then a slim runtime with a JRE, Xpra and the fat jar. |
| `entrypoint.sh` | Refuses to start without a password, warns if `/nets` is not writable, starts Xpra and WoPeD. |
| `Makefile` | The commands above, including running without Docker. |
| `Dockerfile.dockerignore` | Keeps the build context small and secret-free, and keeps edits to these files from re-running the ~4 minute Maven build. |

How the build works: the Maven build skips two modules the image does not need, `WoPeD-Installer`
(it builds Windows/macOS installers and calls `cmd.exe`, which does not exist in the container) and
`WoPeD-UnitTests`. The runnable jar is `WoPeD-Starter/target/*-jar-with-dependencies.jar`.
