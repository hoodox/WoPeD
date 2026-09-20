# Plan: Dockerfile that serves WoPeD in a browser via Xpra

**Status:** IN PROGRESS

## Context

WoPeD is a Java Swing desktop program, so it cannot be deployed as a normal
web page. The chosen way to put it in a browser (agreed in conversation,
2026-09-20) is to run the unchanged desktop program inside a container on a
virtual screen and let Xpra stream that screen to the browser through its
built-in HTML5 client.

Outcome: `docker build` produces one image. `docker run -p 14500:14500` starts
WoPeD, and opening `http://localhost:14500` shows its window in the browser.
No WoPeD source code changes.

## Approach

One multi-stage `Dockerfile` plus a small entrypoint script, both under `images/`. The build context is still the repo root (the multi-module build needs the whole source tree), so the build uses `-f images/Dockerfile .`.

| Stage | Base | Job |
|---|---|---|
| `build` | Maven 3.9 + Temurin JDK `${JAVA_VERSION}` | `mvn install -DskipTests -pl '!WoPeD-Installer,!WoPeD-UnitTests'` (every module except the two the image does not need), producing the runnable jar |
| `runtime` | `eclipse-temurin:${JAVA_VERSION}-jre-jammy` (Ubuntu 22.04) | Xpra + HTML5 client, fonts, a non-root user, the jar, the entrypoint |

Facts verified from source:

- Java version is a build argument `JAVA_VERSION`, **default 17**. All 15 modules
  compile to bytecode level 11 (`maven.compiler.source/target` = 11, e.g.
  `WoPeD-Starter/pom.xml:24-25`), so any JRE >= 11 can run the jar. The project's
  own CI and release build use Temurin **17** (`.github/workflows/ci-java.yaml:24`,
  `cd-release.yml:40`), so 17 is the proven default. The README's "JRE 11" is stale.
  Newer JDKs (21, 25) are **untested**: WoPeD uses JAXB (`javax.xml.bind`, not in
  the JDK since 11) and old libraries (`jgraph`, `log4j` 1.x) that may need
  `--add-opens` flags or an updated Maven plugin. They are tried in Verification
  via `--build-arg JAVA_VERSION=21`, not assumed.
- Temurin's `-jre-jammy` image is used as the runtime base, so the JRE is
  preinstalled at whatever version is requested and only Xpra is added on top.
- Entry point: `org.woped.starter.RunWoPeD` (`WoPeD-Starter/pom.xml:85`), packaged
  by the assembly plugin as a `jar-with-dependencies` (`WoPeD-Starter/pom.xml:81`).
  The version is `${revision}` = `3.9.4` (`pom.xml:13`), so the jar is expected at
  `WoPeD-Starter/target/WoPeD-Starter-3.9.4-jar-with-dependencies.jar`
  (**not yet confirmed by a build** — the Dockerfile globs `*-jar-with-dependencies.jar`
  rather than hard-coding the version).
- Some dependencies come from GitHub Packages, repository id `github`
  (`pom.xml:22-25`), so the build needs a token. It is passed as a BuildKit
  **secret** (a `settings.xml` mounted only during the `mvn` step), never baked
  into an image layer or copied into the build context.
- WoPeD writes its settings to `~/.WoPeD-<version>/` (`WoPeDConfiguration.java:39-45`),
  so the image declares a volume for that folder in the non-root user's home.

Verified by running the runtime stage with a stub Swing jar (2026-09-20):
- Xpra 6.5.3 + `xpra-html5` install from the xpra.org repo on the Temurin jammy base.
  **`xpra-x11` must also be installed** (else Xpra exits: "you must install
  `xpra-x11` to use 'seamless'").
- Swing renders under Xpra with no window manager and no
  `_JAVA_AWT_WM_NONREPARENTING` workaround (the window is registered with Xpra).
- **`--auth=env` alone does NOT protect the browser port.** It attached an
  authenticator only to the unix socket and named pipe; the TCP listener on 14500
  accepted no-password and wrong-password clients. The authenticator must be set on
  the TCP socket itself: `--bind-tcp=0.0.0.0:14500,auth=env`.

Verified by a real build on JDK 17 with the GitHub token (2026-09-20):
- All modules through `WoPeD-Starter` build, and the jar is
  `WoPeD-Starter/target/WoPeD-Starter-3.9.4-jar-with-dependencies.jar` (name confirmed).
- **`WoPeD-Installer` cannot build in a Linux container**: its Ant step runs
  `cmd.exe` (Windows installer packaging) and fails. The image does not need it, so
  the build excludes it and `WoPeD-UnitTests` with `-pl '!WoPeD-Installer,!WoPeD-UnitTests'`.
  (`-pl WoPeD-Starter -am` was tried and does NOT work: Maven's `-am` did not pull
  `WoPeD-BeanMetric` into the reactor, so `WoPeD-CommonLibs` failed to resolve
  `de.dhbw.woped:metricsBeans:3.9.4`, which is not published anywhere.)

Still unverified: running the real WoPeD jar in the browser, other JDKs.

### Before / After

*Before:* no container files exist (verified: no `Dockerfile*`, `.dockerignore`
or `docker*` at the repo root).

*After* — `images/Dockerfile` (key lines only; full file written during implementation):

```dockerfile
# syntax=docker/dockerfile:1.7
ARG JAVA_VERSION=17
FROM maven:3.9-eclipse-temurin-${JAVA_VERSION} AS build
WORKDIR /src
COPY . .
RUN --mount=type=secret,id=m2settings,target=/root/.m2/settings.xml \
    mvn -B install -DskipTests -pl '!WoPeD-Installer,!WoPeD-UnitTests'

FROM eclipse-temurin:${JAVA_VERSION}-jre-jammy AS runtime
# xpra + xpra-x11 + xpra-html5 (xpra.org repo), fonts-dejavu-core
RUN useradd -m woped
COPY --from=build /src/WoPeD-Starter/target/*-jar-with-dependencies.jar /opt/woped/woped.jar
COPY images/entrypoint.sh /opt/woped/entrypoint.sh
USER woped
VOLUME /home/woped
EXPOSE 14500
ENTRYPOINT ["/opt/woped/entrypoint.sh"]
```

*After* — `images/entrypoint.sh` (key line):

```sh
exec xpra start :100 --daemon=no --html=on \
  --bind-tcp=0.0.0.0:14500,auth=env --exit-with-children=yes \
  --start-child="java -Dawt.useSystemAAFontSettings=on -jar /opt/woped/woped.jar"
```

*After* — `images/Dockerfile.dockerignore` (new file; BuildKit reads `<Dockerfile>.dockerignore` from next to the Dockerfile, so no root-level `.dockerignore` is needed): excludes `.git` (713 MB), `**/target`,
and **`.myenv`** — that folder holds a GitLab token in plain text and must never
enter the build context. Also `todos/`, `*.log`.

### Extra host folder for nets (added 2026-09-20, user request)

Goal: `docker run -v "$HOME/woped-nets:/nets" ...` gives WoPeD an **additional** folder on
the host for saving and opening nets. WoPeD's default nets folder is left untouched (the
user chose "extra folder, default untouched" over redirecting the default).

Facts verified from source:
- The default nets folder stays `<user.home>/.WoPeD-<version>/nets/`
  (`WoPeDGeneralConfiguration.java:59`).
- WoPeD's Open/Save dialogs are Swing `JFileChooser`s, which can browse anywhere in the
  container filesystem, so a folder mounted at `/nets` is reachable with no code change.
- WoPeD also has a configurable home directory (`<homedir>` in `WoPeDconfig.xml`, edited via
  the home-directory field in `ConfFilePanel.java:228`; dialogs start there per
  `ConfigVC.java:166-190`). The config file is written when WoPeD exits (observed
  2026-09-20) into the settings volume, so setting it to `/nets` once makes the dialogs
  start there from then on.

Design: no symlink and no file moving. The image only (a) documents `-v host:/nets`, (b) makes
the entrypoint print a warning when `/nets` is mounted but not writable, and (c) adds
`ARG WOPED_UID` / `ARG WOPED_GID` (default 1000) so the container user can match the host
user that owns the folder. `/nets` is deliberately NOT declared a `VOLUME` (that would create
an anonymous volume when nothing is mounted).

*Before:* no way to reach a host folder from inside the container.

*After* — `images/entrypoint.sh` (key lines):

```sh
if [ -d /nets ] && [ ! -w /nets ]; then
  echo "Warning: /nets is not writable by uid $(id -u), saving nets there will fail." >&2
fi
```

### Makefile (added 2026-09-20, user request)

Goal: `make -C images up` builds/runs the image with the password taken from `.myenv/local`
and the extra nets folder mounted at `/nets`, so no long `docker run` line is typed.

Design (all in `images/Makefile`):
- Targets: `help`, `build`, `run` (foreground, Ctrl-C stops), `up` (detached, prints the URL),
  `down`, `logs`. Variables (all prefixed `WOPED_` because generic names such as `NAME`/`PORT`
  collide with the caller's environment: `NAME` was already set in the user's shell, found in
  testing): `WOPED_IMAGE=woped-xpra`, `WOPED_JAVA_VERSION=17`, `WOPED_PORT=14500`,
  `WOPED_BIND=127.0.0.1`, `WOPED_CONTAINER=woped`, `WOPED_HOME_VOLUME=woped-home`,
  `WOPED_ENV_FILE=<repo>/.myenv/local`, `WOPED_M2_SETTINGS` (optional settings.xml override).
- **Nets folder:** default `<repo>/mynets` (`WOPED_DEFAULT_NETS_DIR`). It can be set with
  `WOPED_NETS_DIR` in `.myenv/local`, or on the command line. It is resolved in the shell
  *after* the env file is loaded (a make-time variable could not see the file). Precedence:
  command line / caller's environment beat the env file, which beats the default. A relative
  path is taken relative to the repo root. The folder is created if missing.
- **`.myenv/local.example`:** documents the two settings the Makefile reads from `.myenv/local`
  (`XPRA_PASSWORD`, optional `WOPED_NETS_DIR`), with no echo lines. To let it be committed while
  the real file stays private, `.gitignore` uses `.myenv/*` + `!.myenv/local.example`.
- **Ignore files:** `mynets/` is added to `.gitignore` (nets are user data, not source) and to
  `images/Dockerfile.dockerignore` (otherwise every saved net would invalidate the Maven layer).
- **Password:** the recipe sources `ENV_FILE` with stdout/stderr discarded and requires
  `XPRA_PASSWORD` (from that file or the caller's environment). Sourcing must be silent because
  the existing `.myenv/local` echoes a token when sourced. The value is passed as
  `-e XPRA_PASSWORD` (name only), so it never appears in `make` output, `ps` or `docker inspect`
  args; recipe lines use `@`. Only `XPRA_PASSWORD` is forwarded into the container, not the
  other variables in that file. The Makefile never writes the password anywhere.
- **Build token:** `build` writes a temporary mode-600 `settings.xml` from `gh auth token` and
  deletes it on exit, so there is no stale copy; `M2_SETTINGS=<file>` uses an existing one.
  `WOPED_UID`/`WOPED_GID` come from the calling user's `id` (1000 if root) so the mounted folder
  is writable.
- **Build cache fix:** `images/Dockerfile.dockerignore` gets `images/*` + `!images/entrypoint.sh`
  so editing the Dockerfile/Makefile no longer invalidates the `COPY . .` layer (which re-ran the
  ~4 minute Maven build). The Dockerfile itself is still sent to the builder.

## Scope

In: `images/Dockerfile`, `images/Dockerfile.dockerignore`, `images/entrypoint.sh`, `images/Makefile`, `.myenv/local.example` and `images/README.md` (added 2026-09-20 at user request), a default nets folder `<repo>/mynets/`, and (added 2026-09-20 at user request) an optional extra host folder for nets, mounted at `/nets`, with WoPeD's default nets folder left untouched.
Out: docker-compose, TLS/reverse proxy, multi-user session management, CI image
publishing, any change to WoPeD Java code. Default is **one container = one
session** (Xpra's own password protects it).

## Sequence diagrams

> Provisional — drafted by the assistant, not yet approved by the repo owner.

How a browser reaches WoPeD once the container is running.

```mermaid
sequenceDiagram
    autonumber
    participant Browser
    participant Xpra as Xpra server
    participant Screen as Virtual display
    participant App as WoPeD JVM
    Note right of Xpra: images/entrypoint.sh starts xpra on :100
    Note right of App: RunWoPeD in WoPeD-Starter jar
    Browser->>Xpra: GET / on port 14500 (HTML5 client)
    Xpra-->>Browser: HTML5 client page
    Browser->>Xpra: connect + password
    alt password wrong
        Xpra-->>Browser: reject
    else password ok
        Xpra->>App: start-child java -jar woped.jar
        App->>Screen: draw Swing window
        Screen-->>Xpra: window pixels
        Xpra-->>Browser: stream window
        Browser->>Xpra: mouse and key events
        Xpra->>App: forward input
    end
    Note over Xpra,App: App exits so Xpra exits so container stops
```

## Implementation

**Folders touched** (check `.claude/rules/` for each before coding):
- `images/` (new) → no scoped rule (`.claude/rules/` does not exist in this repo)

**Flow:** see `## Sequence diagrams`

1. Create `images/Dockerfile.dockerignore` (exclude `.git`, `**/target`, `.myenv`, `todos`, `*.log`, IDE folders).
2. Create `images/entrypoint.sh` (executable): require `XPRA_PASSWORD`, then the `exec xpra start ...` line above.
3. Create `images/Dockerfile` with the `build` and `runtime` stages above.
   - add the xpra.org apt repo for Ubuntu 22.04 in the runtime stage, install `xpra xpra-html5`
4. Confirm the real jar name from the build output and tighten the `COPY` glob if needed.
5. Build once with the default (17). Then try `--build-arg JAVA_VERSION=21` and record in `## Status` whether the app starts and works; if it needs `--add-opens` flags, add them to the entrypoint only when 21 is chosen as the default.
6. Record the build and run commands in the Verification results (no README edit — out of scope).
7. `images/Dockerfile`: add `ARG WOPED_UID/WOPED_GID` (default 1000) used by `groupadd`/`useradd`; document `-v ~/woped-nets:/nets` and the optional home-directory step in the header comment.
8. `images/entrypoint.sh`: if `/nets` exists and is not writable, print a warning (do not fail).
9. Verify (see Verification, "Extra nets folder").
10. `images/Dockerfile.dockerignore`: add `images/*` and `!images/entrypoint.sh` (with a comment why).
11. Create `images/Makefile` per the Makefile subsection in Approach.
12. Create `.myenv/local.example`; add `mynets/` to `.gitignore` and `images/Dockerfile.dockerignore`; change `.gitignore`'s `.myenv/` to `.myenv/*` + `!.myenv/local.example`.
13. Verify the Makefile (Verification, "Makefile").
14. Write `images/README.md`: what it is, requirements, quick start, settings, targets/variables, nets folder, Java version, plain-docker commands, security notes, troubleshooting. Only document behaviour verified in this plan. (It is excluded from the Docker build context by the `images/*` ignore rule, so editing it never triggers a rebuild.)

## Verification

Prerequisites: Docker 29.4.1 with buildx is installed locally (checked 2026-09-20).
A `~/.m2/settings.xml`-format file holding a GitHub token with `read:packages`
must exist at a path outside the repo, e.g. `~/.woped-m2-settings.xml`.

```bash
DOCKER_BUILDKIT=1 docker build -f images/Dockerfile --secret id=m2settings,src=$HOME/.woped-m2-settings.xml -t woped-xpra .
docker run --rm -e XPRA_PASSWORD=changeme -p 14500:14500 woped-xpra
```

Auth check (do not use `xpra ... --password=...`: Xpra 6 silently ignores that flag, so a
"wrong password" test would really send none). Pass the password in the URL and strip the
container's own `XPRA_PASSWORD` from the client, because `docker exec` inherits it:

```bash
run() { docker exec <ctr> env -u XPRA_PASSWORD XDG_RUNTIME_DIR=/tmp/xdg-runtime "$@"; }
run xpra info tcp://127.0.0.1:14500            # expect: rejected (authentication required)
run xpra info tcp://u:wrong@127.0.0.1:14500    # expect: rejected
run xpra info tcp://u:<password>@127.0.0.1:14500   # expect: window info; repeat with ws://
```

Extra nets folder (host directory, added 2026-09-20):
```bash
mkdir -p ~/woped-nets
docker run --rm -e XPRA_PASSWORD -v ~/woped-nets:/nets -v woped-home:/home/woped -p 127.0.0.1:14500:14500 woped-xpra
```
- `docker exec <ctr> sh -c 'touch /nets/x'` succeeds and the file appears in `~/woped-nets` on the host, owned by the host user.
- The default `/home/woped/.WoPeD-<ver>/nets` is still a real folder (not a link) and its files are unchanged.
- Without the `-v ...:/nets` mount, behaviour is unchanged and `/nets` does not exist.
- A non-writable mount prints the warning and the container still starts.
- Set WoPeD's home directory to `/nets` (its Configuration dialog), quit, restart: the Open/Save dialogs start in `/nets` (checked by the user in the browser).

Makefile (added 2026-09-20):
- `make -C images help` lists targets and variables.
- `make -C images up` with no `XPRA_PASSWORD` anywhere fails with a clear message and starts nothing.
- With a temporary `WOPED_ENV_FILE` (a fake secret in an `echo` line, a test password, a `WOPED_NETS_DIR`): neither the fake secret nor the password appears in `make` output, the container receives the password, `/nets` is mounted from that folder, no-password clients are rejected. A `WOPED_NETS_DIR=` on the command line beats the file; with neither, the folder is `<repo>/mynets`. With the real `.myenv/local`, the GitLab token it echoes is not in the `make` output.
- `make -C images down` removes the container. `make -C images build` succeeds and reuses the Maven layer on a second run after touching only `images/Makefile`.

Expected:
0. Repeat the whole list with `--build-arg JAVA_VERSION=21` (and 25 if desired) and note pass/fail per version in `## Status`. Default stays 17 unless a newer one passes cleanly.
1. Build succeeds; `docker history woped-xpra` shows no token and the image contains no `.myenv` (`docker run --rm --entrypoint ls woped-xpra -a /opt/woped`).
2. `curl -sI http://localhost:14500/` returns `200`.
3. Opening `http://localhost:14500` prompts for the password, then shows the WoPeD main window (menu/ribbon renders, not a blank frame).
4. Create and save a small net, restart the container with `-v woped-home:/home/woped`, and confirm settings/recent files persist.
5. Closing WoPeD stops the container.

## Risks & rollback

- **Bind-mount permissions:** the container user (default uid/gid 1000, verified in the image) must be able to write the host folder. If the host user is not 1000, build with `--build-arg WOPED_UID=$(id -u) --build-arg WOPED_GID=$(id -g)`. A `-v` to a missing host path makes Docker create it root-owned: `mkdir` it first (or use `--mount type=bind`, which errors instead).
- **Dialogs still start in the default folder** until the home directory is set to `/nets` in WoPeD's Configuration; nets already saved in the default folder are not moved.
- **`.myenv/local` echoes a secret when sourced** (existing file): the Makefile discards its output; do not `source` it in a terminal where output is logged. The file is mode 644 (world-readable): `chmod 600` it. `build` needs `gh` logged in with `read:packages` (or `M2_SETTINGS`).
- **Newer JDK breaks at build or runtime** (removed/encapsulated APIs, old plugins): keep the default at 17, which CI proves.
- **Blank/grey Swing window** under Xpra without a window manager: add
  `_JAVA_AWT_WM_NONREPARENTING=1` to the entrypoint, or install a light WM.
- **xpra.org repo / package names** for jammy may differ from assumed: fall back
  to Ubuntu's own (older) `xpra` package, or pin a version.
- **Port 14500 must be password-protected on the TCP socket itself**: found during
  verification that `--auth=env` alone leaves TCP open. The entrypoint refuses to
  start when `XPRA_PASSWORD` is unset and sets `auth=env` on `--bind-tcp`. Verify
  no-password and wrong-password clients are rejected after any Xpra change. The
  password still travels unencrypted over plain TCP/WS: do not publish the port on
  a public host without TLS in front.
- Rollback: delete the `images/` folder; nothing else changes.

## Open questions

- One container per user (current default), or one shared demo instance? A shared
  instance would need Xpra's `--sharing=yes` and an explicit decision on who may edit.
- Where will it be hosted? That decides whether a TLS reverse proxy plan is needed.

## Dependencies

### Blocks this plan (must be done first)
- A GitHub token with `read:packages` in a settings file outside the repo — DONE (2026-09-20: `gh auth refresh -s read:packages`, then `~/.woped-m2-settings.xml` generated from `gh auth token`, mode 600). The file is a copy: regenerate it after any later `gh auth refresh`, or the build will 401.

### Blocked by this plan (cannot start until this is done)
- None.

## Status

- 2026-09-20 (WoPeD fork): PLANNED — plan written; awaiting user approval (`APPROVED`) before any Dockerfile is created.
- 2026-09-20 (WoPeD fork): PLANNED / NEEDS RE-REVIEW — approach changed after user asked about newer Java: `JAVA_VERSION` build arg (default 17, matching CI) and a Temurin JRE runtime base replace the fixed JDK 11 + Ubuntu 22.04 setup; 21/25 to be tried during verification. Awaiting user approval.
- 2026-09-20 (WoPeD fork): APPROVED — user approved the plan (including the `JAVA_VERSION` build-arg change, which closes the NEEDS RE-REVIEW flag). Open questions keep their defaults: one container per session, hosting undecided (no TLS plan yet).
- 2026-09-20 (WoPeD fork): IN PROGRESS — creating `.dockerignore`, `docker/entrypoint.sh`, `Dockerfile`. Implemented inline by the driver (small plan, three files). No GitHub `read:packages` token yet, so the full build may not be verifiable.
- 2026-09-20 (WoPeD fork): IN PROGRESS — user asked for the docker files under `images/`. Plan updated first: files are `images/Dockerfile`, `images/Dockerfile.dockerignore`, `images/entrypoint.sh`; build context stays the repo root, build command uses `-f images/Dockerfile .`. Files created earlier at the repo root and `docker/` are being moved there.
- 2026-09-20 (WoPeD fork): IN PROGRESS — files created under `images/`. Full build without a GitHub token fails at `mvn` with 401 on `de.dhbw.woped:jgraph:5.10.2` from GitHub Packages (token really required). Runtime stage tested with a stub Swing jar: added missing `xpra-x11` package; Swing window registers under Xpra; HTTP 200 on 14500. **Security defect found:** `--auth=env` did not protect the TCP port (no-password and wrong-password clients got in). Fixing by moving auth onto `--bind-tcp=...,auth=env` and re-testing before continuing.
- 2026-09-20 (WoPeD fork): IN PROGRESS — auth fixed and verified with a stub Swing jar on the real entrypoint: over both `tcp://` and `ws://` no-password and wrong-password clients are rejected, right password gets window info (earlier "wrong password" runs were invalid: Xpra 6 ignores `--password=`). Done: `.dockerignore` verified to keep `.myenv` and `.git` out of the context (44 MB vs 713 MB). NOT yet done: build with the real WoPeD jar and check the UI in a browser (blocked on a GitHub `read:packages` token, see Dependencies), the `JAVA_VERSION=21/25` runs, and the persistence/exit checks. Plan stays IN PROGRESS until those pass.
- 2026-09-20 (WoPeD fork): IN PROGRESS — first real build (JDK 17, token from `~/.woped-m2-settings.xml`): all modules through WoPeD-Starter built and the fat jar was produced; `WoPeD-Installer` failed (Ant `<exec executable="cmd.exe">`, Windows-only). Changing the Dockerfile to `mvn -B install -DskipTests -pl WoPeD-Starter -am`, then rebuilding.
- 2026-09-20 (WoPeD fork): IN PROGRESS — `-pl WoPeD-Starter -am` failed (`metricsBeans:3.9.4` unresolved: `-am` did not include WoPeD-BeanMetric). Switching to excluding only `WoPeD-Installer` and `WoPeD-UnitTests`; rebuilding.
- 2026-09-20 (WoPeD fork): IN PROGRESS — verification results with the real WoPeD jar. **Build:** `mvn install -DskipTests -pl '!WoPeD-Installer,!WoPeD-UnitTests'` succeeds on JDK 17 (image 1.12 GB) and on JDK 21 (`--build-arg JAVA_VERSION=21`, image 1.15 GB). **Run (17 and 21):** container stays up, `GET /` = 200, Xpra registers the window `WoPeD 3.9.4` (800x600), no-password and wrong-password clients rejected, no Java exceptions/`InaccessibleObject` errors in `woped.log` or container log on 21. **Persistence:** `.WoPeD-3.9.4/` and `woped.log` written to the `/home/woped` volume and still present in a new container on the same volume. **Exit:** stopping the Java process stops the container. **Browser:** the HTML5 client loads and shows the password prompt; the post-login UI was NOT viewed (the assistant does not type passwords), so the visual check is left to the user. Only startup was exercised on 21, not features (open/save/analysis). JDK 25 not tried. Default stays 17 (proven by CI). Benign log noise: missing `paramiko`, DRM query, and `libx264` (x264 video encoder unavailable, Xpra falls back to other encoders). Plan moves to DONE once the user confirms the UI renders in a browser.
- 2026-09-20 (WoPeD fork): IN PROGRESS — the demo container log shows a real browser session: an HTML5 Chrome client passed the password challenge at 15:19:10 and was served ~2.6 MB of window updates until the WoPeD process ended at 15:20:55, after which Xpra exited the container with code 0 (`--exit-with-children`). Consistent with the browser and exit checks passing. Still waiting for the user to confirm the UI looked right before moving to DONE.
- 2026-09-20 (WoPeD fork): IN PROGRESS — user asked for an option to store nets in a local directory. Added to the plan first (Approach subsection, Implementation 7-9, Verification, Risks): mount a host folder at `/nets`, entrypoint symlinks WoPeD's default `.WoPeD-<version>/nets` to it; version captured at build time. Scope addition was requested by the user directly; no re-review flag needed.
- 2026-09-20 (WoPeD fork): IN PROGRESS — user asked whether the host folder is separate from the default one. Answer: no, the default `nets/` becomes a symlink to `/nets` when mounted. Found the user's settings volume already holds an autosave `.pnml` in the default `nets/`, so the entrypoint rule changed from "leave a non-empty nets/ alone" to "move its files into /nets without overwriting, then link". Plan updated before code.
- 2026-09-20 (WoPeD fork): IN PROGRESS — user chose "extra folder, default untouched". The earlier symlink-and-move design (never tested) is dropped and its draft code removed. Plan now: mount a host folder at `/nets`, warn if not writable, `WOPED_UID/GID` build args; optionally set `/nets` as WoPeD's home directory in its Configuration dialog.
- 2026-09-20 (WoPeD fork): IN PROGRESS — extra nets folder implemented and verified. Entrypoint tested on the existing image: writable `-v <dir>:/nets` (file written in the container appears on the host owned by the host user, default `.WoPeD-3.9.4/nets` stays a real folder, no warning), no mount (unchanged, `/nets` absent, no warning), non-writable mount (warning printed, container still starts). Rebuilt image (JDK 17) end to end: HTTP 200, `WoPeD 3.9.4` window registered, no-password client still rejected, `/nets` writable from the container. `--build-arg WOPED_UID=1234 --build-arg WOPED_GID=1234` gives `uid=1234(woped)`. `woped-xpra:latest` = this build. NOT yet checked: setting `/nets` as WoPeD's home directory in its Configuration dialog and seeing the dialogs start there (left to the user in the browser). The `woped-xpra:21` image predates this change (no `/nets` warning) — rebuild it with `--build-arg JAVA_VERSION=21` if needed.
- 2026-09-20 (WoPeD fork): IN PROGRESS — user asked for a Makefile that takes the password from `.myenv/local` and passes the extra folder. Plan updated first (Approach subsection, Implementation 10-12, Verification, Risks). Also fixing the ignore file so edits under `images/` stop invalidating the Maven build layer.
- 2026-09-20 (WoPeD fork): IN PROGRESS — user asked for a `local.example` and for the extra folder to default to `<repo>/mynets`. Plan updated first: default folder `<repo>/mynets`, settable via `WOPED_NETS_DIR` in `.myenv/local` (resolved after loading the file, command line wins), `.myenv/local.example` added, ignore files updated. Also renamed all Makefile variables to `WOPED_*` after `NAME` from the caller's environment overrode the container name.
- 2026-09-20 (WoPeD fork): IN PROGRESS — Makefile, `.myenv/local.example` and default folder `<repo>/mynets` implemented and verified. **Makefile:** `help` lists targets/variables. Missing `XPRA_PASSWORD` (checked with the user's real `.myenv/local`) fails with a clear message, starts nothing, creates no folder, and the GitLab token that file echoes does not appear in the output. With a temporary env file (fake secret in an `echo`, test password, `WOPED_NETS_DIR`): password and fake secret absent from `make` output, container env password matches, only `XPRA_PASSWORD` is forwarded (no GITLAB vars), `/nets` mounted from the file's folder, file written in the container appears on the host, no-password client rejected and right password accepted, port bound to `127.0.0.1` only. Precedence checked: command line beats env file. Default (nothing configured) mounts `<repo>/mynets`; a relative path resolves against the repo root; `mynets/` is invisible to git. `make down` stops the container. **`make build`:** succeeds with the temporary token file generated from `gh` and removed afterwards (none left in `/tmp`). **Cache:** after adding `images/*` / `!images/entrypoint.sh` to the ignore file, changing only `images/Makefile` rebuilds in 2 s (Maven layer cached) instead of ~4 min. `woped-xpra:latest` = current build. NOT verified: the user's own password in their real `.myenv/local` (they have not added `XPRA_PASSWORD` yet) and the browser step (setting `/nets` as home directory).
- 2026-09-20 (WoPeD fork): IN PROGRESS — user asked for a README in `images/`. Plan updated first (Scope, Implementation 14); README documents only verified behaviour.
- 2026-09-20 (WoPeD fork): IN PROGRESS — `images/README.md` written and checked against the real files: every `WOPED_*` variable it names exists in the Makefile, the Java 21 command (`WOPED_JAVA_VERSION=21 WOPED_IMAGE=...:21`) and the `WOPED_M2_SETTINGS` override resolve correctly in a `make -n` dry run (also from inside `images/`), all referenced files exist, and editing only the README rebuilds in 3 s with the Maven layer cached (README is excluded from the build context by the `images/*` ignore rule). Remaining before DONE: user confirms the browser UI, and the `/nets` home-directory step.
